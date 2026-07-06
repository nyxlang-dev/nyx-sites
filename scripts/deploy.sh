#!/bin/bash
# deploy.sh — nyx-sites: build → smoke → units → restart secuencial verificado.
#
# Reemplaza el loop de sites del deploy.sh del monorepo NyxLang (split #6,
# 2026-07-06). El gateway (:443) NO se toca acá — vive en el monorepo
# (services/gateway) hasta el split #7.
#
# Orden de restart: serve-web → proxy-web → landing-main (el default
# upstream del gateway al final, con el procedimiento ya validado 2 veces).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[1/4] Vendor + build..."
bash scripts/vendor_nyx_serve.sh
make build-all

echo "[2/4] Smoke efímero..."
bash scripts/smoke.sh

echo "[3/4] Units systemd..."
sudo cp deploy/nyx-landing-main.service deploy/nyx-serve-web.service \
        deploy/nyx-proxy-web.service /etc/systemd/system/
sudo systemctl daemon-reload

echo "[4/4] Restart secuencial verificado..."
declare -A PORTS=([nyx-serve-web]=3003 [nyx-proxy-web]=3005 [nyx-landing-main]=3001)
for unit in nyx-serve-web nyx-proxy-web nyx-landing-main; do
    port="${PORTS[$unit]}"
    sudo systemctl restart "$unit"
    ok=0
    for _ in $(seq 1 50); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null || true)
        if [ "$code" = "200" ]; then ok=1; break; fi
        sleep 0.2
    done
    if [ "$ok" = "1" ]; then
        echo "  ✓ $unit (:$port → 200)"
    else
        echo "  ✗ $unit (:$port → ${code:-sin respuesta}) — ABORTO antes de tocar el siguiente"
        exit 1
    fi
done
echo "Deploy completo."
