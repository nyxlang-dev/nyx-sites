#!/bin/sh
# scripts/inline-mockup.sh — mockup AUTOCONTENIDO de la landing generada.
#
# Toma la salida de `nyx gen.nx --out <dir>` y produce un HTML que se abre a
# doble clic desde cualquier lado: el <link> a /shared/spec.css pasa a ser un
# <style> con la hoja adentro y el <script src="/shared/copy.js"> pasa a ser un
# <script> con el JS adentro. No cambia NADA más del HTML — es exactamente la
# página generada, sin rutas absolutas a los assets.
#
# Uso:  sh scripts/inline-mockup.sh [<dir-generado>] [<dir-destino>]
#       (por defecto: nyxlang.com/static-next  →  /tmp/nyx-mockup)
set -e

ROOT="${1:-nyxlang.com/static-next}"
DEST="${2:-/tmp/nyx-mockup}"

CSS="$ROOT/shared/spec.css"
JS="$ROOT/shared/copy.js"
for f in "$CSS" "$JS"; do
    [ -f "$f" ] || { echo "error: falta $f — hay que correr \`make gen\` primero" >&2; exit 1; }
done
mkdir -p "$DEST"

inline() {
    src="$1"
    out="$2"
    [ -f "$src" ] || { echo "error: falta $src" >&2; exit 1; }
    awk -v cssf="$CSS" -v jsf="$JS" '
        /<link rel="stylesheet" href="\/shared\/spec.css">/ {
            print "<style>"
            while ((getline line < cssf) > 0) print line
            close(cssf)
            print "</style>"
            next
        }
        /<script src="\/shared\/copy.js" defer><\/script>/ {
            print "<script>"
            while ((getline line < jsf) > 0) print line
            close(jsf)
            print "</script>"
            next
        }
        { print }
    ' "$src" > "$out"
    # Guarda: si quedó una referencia a /shared el mockup NO es autocontenido.
    if grep -q 'href="/shared\|src="/shared' "$out"; then
        echo "error: $out todavía referencia /shared" >&2
        exit 1
    fi
    echo "  $out"
}

echo "mockup autocontenido:"
inline "$ROOT/index.html"    "$DEST/mockup-en.html"
inline "$ROOT/es/index.html" "$DEST/mockup-es.html"
