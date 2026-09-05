#!/bin/bash
# smoke.sh — levanta cada binario en un puerto efímero 131xx, verifica
# HTTP 200 en / y lo baja. NO toca los servicios de producción.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
declare -A BINS=(
    ["nyxlang.com/nyxlang-com"]=13101
    ["serve.nyxlang.com/serve-nyxlang-com"]=13103
    ["proxy.nyxlang.com/proxy-nyxlang-com"]=13105
    ["edit.nyxlang.com/edit-nyxlang-com"]=13109
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

    # nyxlang.com: rutas extra del rediseño. /docs/ y /es/docs/ existen o no
    # según la raíz servida (NYX_STATIC_ROOT) — solo exigimos 200 cuando el
    # directorio está presente bajo esa raíz; si no, alcanza con que no sea
    # un 500 (404 limpio es el contrato de app_static_cached).
    if [ "$rel" = "nyxlang.com/nyxlang-com" ] && [ "$ok" = "1" ]; then
        static_root="${NYX_STATIC_ROOT:-static}"
        check_path() {
            local path="$1" want="$2"
            local got
            got=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$path" 2>/dev/null || true)
            if [ "$got" = "$want" ]; then
                echo "  PASS $rel$path (→ $got)"
            else
                echo "  FAIL $rel$path (→ ${got:-sin respuesta}, esperaba $want)"
                fail=1
            fi
        }
        check_path "/by-example/" "200"
        check_path "/learn/01.html" "200"
        for docs_path in "/docs/" "/es/docs/"; do
            docs_dir="$site_dir/$static_root${docs_path%/}"
            if [ -d "$docs_dir" ]; then
                check_path "$docs_path" "200"
            else
                got=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$docs_path" 2>/dev/null || true)
                if [ "$got" = "404" ]; then
                    echo "  PASS $rel$docs_path (sin contenido, → 404 limpio)"
                else
                    echo "  FAIL $rel$docs_path (→ ${got:-sin respuesta}, esperaba 404)"
                    fail=1
                fi
            fi
        done
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
done
if [ "$fail" = "0" ]; then echo "smoke: 4/4 PASS"; else echo "smoke: HAY FALLOS"; exit 1; fi
