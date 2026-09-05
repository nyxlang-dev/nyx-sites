#!/bin/sh
# check-doc-blocks.sh — cada bloque de Nyx de la guía /docs COMPILA.
#
# Uso: sh scripts/check-doc-blocks.sh <dir-de-salida>      (p.ej. static-next)
#
# Recorre <dir>/docs/*.html y <dir>/es/docs/*.html, extrae el contenido de cada
# <pre data-lang="nyx">, le saca los <span> del resaltado, des-escapa las
# entidades y compila el resultado. La guía promete que sus ejemplos andan; esto
# es lo que convierte esa promesa en algo refutable.
#
# El atributo data-fragment del <pre> dice CÓMO se verifica el bloque:
#   (ausente)  programa completo: se compila y se ejecuta con `nyx <archivo>`
#   "1"        fragmento sin fn main: se envuelve en `fn main() { … }` y se compila
#   "test"     bloques `test "…" { }`: se copian a tests/ de un proyecto de
#              scratch y se corren con `nyx test`
#   "error"    el bloque ILUSTRA un error de compilación: se exige que NO
#              compile (si algún día compilara, el texto de al lado sería falso)
#
# Por qué `nyx <archivo>` y no `nyx check`: `nyx check` no resuelve el prelude
# (Option/Result salen como NYX1002 aunque el programa compile y corra) — está
# documentado en los reportes de la T1 y la T2 de este rediseño. `nyx <archivo>`
# compila, linkea y ejecuta: es la verificación fuerte, no la barata.

set -e

OUT="${1:-static-next}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/nyx-docblocks.$$"
FAILED=0
TOTAL=0

if [ ! -d "$OUT/docs" ]; then
    echo "error: no existe « $OUT/docs » (¿corriste 'make gen'?)" >&2
    exit 1
fi

mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Proyecto de scratch para los bloques data-fragment="test": `nyx test` exige
# un nyx.toml y un src/main.nx, y corre TODO tests/*.nx, así que cada bloque
# entra solo y se borra antes del siguiente.
mkdir -p "$WORK/proj/src" "$WORK/proj/tests"
cat > "$WORK/proj/nyx.toml" <<'TOML'
[package]
name = "docblocks"
version = "0.1.0"
main = "src/main.nx"

[dependencies]
TOML
printf 'fn main() {\n    print("docblocks")\n}\n' > "$WORK/proj/src/main.nx"

# Extrae los bloques de UN archivo. Deja <dest>/NNN.nx (el código ya limpio) y
# <dest>/NNN.mode (el valor de data-fragment, vacío si no lo tenía).
extract() {
    awk -v dest="$2" '
        # Abre un bloque: todo lo que sigue al ">" del tag inicial ya es código.
        /<pre data-lang="nyx"/ && !inblock {
            inblock = 1
            n = n + 1
            mode = ""
            if (match($0, /data-fragment="[^"]*"/)) {
                mode = substr($0, RSTART + 15, RLENGTH - 16)
            }
            printf "%s", mode > sprintf("%s/%03d.mode", dest, n)
            close(sprintf("%s/%03d.mode", dest, n))
            file = sprintf("%s/%03d.raw", dest, n)
            sub(/^.*<pre data-lang="nyx"[^>]*>/, "")
            if ($0 !~ /<\/pre>/) { print > file; next }
        }
        inblock {
            if ($0 ~ /<\/pre>/) {
                sub(/<\/pre>.*$/, "")
                print > file
                close(file)
                inblock = 0
                next
            }
            print > file
        }
    ' "$1"
}

# Saca los tags del resaltado y des-escapa. &amp; va ÚLTIMO: si no, un
# `&amp;lt;` del fuente volvería a ser "<" en vez de "&lt;".
unhtml() {
    sed -e 's/<[^>]*>//g' \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&quot;/"/g' \
        -e "s/&#x27;/'/g" \
        -e "s/&#39;/'/g" \
        -e 's/&amp;/\&/g' "$1"
}

for dir in "$OUT/docs" "$OUT/es/docs"; do
    [ -d "$dir" ] || continue
    for html in "$dir"/*.html; do
        [ -f "$html" ] || continue
        blocks="$WORK/$(echo "$html" | tr '/' '_')"
        mkdir -p "$blocks"
        extract "$html" "$blocks"
        for raw in "$blocks"/*.raw; do
            [ -f "$raw" ] || continue
            TOTAL=$((TOTAL + 1))
            idx="$(basename "$raw" .raw)"
            mode="$(cat "$blocks/$idx.mode" 2>/dev/null || true)"
            src="$blocks/$idx.nx"
            unhtml "$raw" > "$src"
            label="$html [$idx]"

            case "$mode" in
                test)
                    rm -f "$WORK/proj/tests"/*.nx
                    cp "$src" "$WORK/proj/tests/block_test.nx"
                    if (cd "$WORK/proj" && nyx test) > "$blocks/$idx.log" 2>&1 \
                       && grep -q 'ALL TESTS PASSED' "$blocks/$idx.log"; then
                        echo "  ok   $label (test)"
                    else
                        echo "  FAIL $label (test)"
                        sed 's/^/       /' "$blocks/$idx.log" | tail -12
                        FAILED=$((FAILED + 1))
                    fi
                    ;;
                error)
                    if nyx "$src" > "$blocks/$idx.log" 2>&1; then
                        echo "  FAIL $label (debía NO compilar, y compiló)"
                        FAILED=$((FAILED + 1))
                    else
                        echo "  ok   $label (no compila, como dice el texto)"
                    fi
                    ;;
                1)
                    {
                        echo "fn main() {"
                        sed 's/^/    /' "$src"
                        echo "}"
                    } > "$blocks/$idx.wrapped.nx"
                    if nyx "$blocks/$idx.wrapped.nx" > "$blocks/$idx.log" 2>&1; then
                        echo "  ok   $label (fragmento)"
                    else
                        echo "  FAIL $label (fragmento)"
                        grep -E 'error|✗' "$blocks/$idx.log" | head -6 | sed 's/^/       /'
                        FAILED=$((FAILED + 1))
                    fi
                    ;;
                *)
                    if nyx "$src" > "$blocks/$idx.log" 2>&1; then
                        echo "  ok   $label"
                    else
                        echo "  FAIL $label"
                        grep -E 'error|✗' "$blocks/$idx.log" | head -6 | sed 's/^/       /'
                        FAILED=$((FAILED + 1))
                    fi
                    ;;
            esac
        done
    done
done

echo ""
if [ "$TOTAL" -eq 0 ]; then
    echo "error: no se encontró ningún bloque <pre data-lang=\"nyx\"> en $OUT" >&2
    exit 1
fi
if [ "$FAILED" -gt 0 ]; then
    echo "check-doc-blocks: $FAILED de $TOTAL bloque(s) NO compilan"
    exit 1
fi
echo "check-doc-blocks: $TOTAL/$TOTAL bloques compilan"
