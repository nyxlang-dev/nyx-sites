#!/bin/bash
# vendor_nyx_serve.sh — re-vendoriza la lib nyx-serve en los 3 sites.
#
# Copia SIEMPRE (no "solo si falta" — eso dejaba copias stale en el
# monorepo) desde ~/nyx-serve-stack hacia <site>/packages/nyx-serve/.
# El vendoring está COMMITEADO en este repo: build determinista sin red,
# pin explícito. Actualizar la lib = correr este script + commit del diff.
set -e
SITES_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVE_STACK="${NYX_SERVE_STACK:-$HOME/nyx-serve-stack}"

if [ ! -f "$SERVE_STACK/src/server.nx" ]; then
    echo "ERROR: no encuentro nyx-serve en $SERVE_STACK (clonar nyxlang-dev/nyx-serve-stack o exportar NYX_SERVE_STACK)"
    exit 1
fi

for site in nyxlang.com serve.nyxlang.com proxy.nyxlang.com; do
    dest="$SITES_ROOT/$site/packages/nyx-serve"
    mkdir -p "$dest/src"
    cp "$SERVE_STACK"/src/*.nx "$dest/src/"
    cp "$SERVE_STACK"/nyx.toml "$dest/"
    echo "  ✓ $site ← nyx-serve $(grep '^version' "$SERVE_STACK/nyx.toml" | head -1 | cut -d'"' -f2)"
done
echo "Vendoring actualizado. Revisar 'git diff' y commitear el pin nuevo."
