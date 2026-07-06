#!/bin/bash
# smoke.sh — levanta cada binario en un puerto efímero 131xx, verifica
# HTTP 200 en / y lo baja. NO toca los servicios de producción.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
declare -A BINS=(
    ["nyxlang.com/nyxlang-com"]=13101
    ["serve.nyxlang.com/serve-nyxlang-com"]=13103
    ["proxy.nyxlang.com/proxy-nyxlang-com"]=13105
)
fail=0
for rel in "${!BINS[@]}"; do
    port="${BINS[$rel]}"
    site_dir="$ROOT/$(dirname "$rel")"
    bin="$ROOT/$rel"
    if [ ! -x "$bin" ]; then echo "  FAIL $rel: binario no existe (make build-all)"; fail=1; continue; fi
    # static/ se resuelve relativo al cwd → correr desde el dir del site.
    # exec: que $! sea el PID del binario, no del subshell (si no, el kill
    # mata al bash intermedio y el daemon queda huérfano escuchando).
    (cd "$site_dir" && exec env PORT=$port "$bin" >/dev/null 2>&1) &
    pid=$!
    ok=0
    for _ in $(seq 1 50); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null || true)
        if [ "$code" = "200" ]; then ok=1; break; fi
        sleep 0.2
    done
    if [ "$ok" = "1" ]; then echo "  PASS $rel (:$port → 200)"; else echo "  FAIL $rel (:$port → ${code:-sin respuesta})"; fail=1; fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
done
if [ "$fail" = "0" ]; then echo "smoke: 3/3 PASS"; else echo "smoke: HAY FALLOS"; exit 1; fi
