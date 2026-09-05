#!/usr/bin/env bash
# gen-site.sh — orquesta la generación completa de nyxlang.com/static-next.
#
# static-next/ lleva DOS cosas:
#   1. lo que gen.nx genera de verdad: la landing, la guía /docs, el recetario
#      /by-example (desde la fase 2) y shared/{spec.css,copy.js}
#   2. una copia PARCHEADA del único contenido LEGADO que el sitio sigue
#      sirviendo: «The Nyx Book» (static/learn/, static/es/learn/), su hoja de
#      estilos (static/shared/nyx-design-system.css) y el shim static/install.sh.
#      El libro ya no se mantiene, pero sus URLs siguen respondiendo 200.
#
# El parche (sobre la COPIA, nunca sobre static/) retira el ancla muerta
# /#products y la columna de footer con nombres de producto, y agrega un banner
# "este libro ya no se mantiene" + <meta name="robots" content="noindex,follow">
# en cada página del libro.
#
# DEUDA CONOCIDA (la última que queda de identidad vieja): las 74 páginas de
# learn/ y es/learn/ cargan Google Fonts. El check D de check-content.sh lo
# detectaría, pero learn/ está exento por ser legado permanente. Se salda el día
# que el libro se regenere o se retire; el recetario ya salió de esa lista.
#
# Idempotencia — dos mecanismos, porque la fuente ya no es pristina:
#   · los directorios legado destino se BORRAN y se copian de nuevo desde
#     static/ en cada corrida;
#   · los parches se aplican con GUARDA (si la marca ya está, no se repite).
#     Desde el swap de la fase 1, static/ ES la copia ya parcheada — el árbol
#     original del libro no existe más — así que un parche que se aplicara dos
#     veces duplicaría el banner y el <meta robots>. Dos corridas seguidas
#     dejan el árbol git-idéntico.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="$REPO_ROOT/nyxlang.com"
cd "$SITE_DIR"

# ── 0. Lo que gen.nx pasó a producir y antes se copiaba ─────────────────────
# El recetario se GENERA desde la fase 2. Sin este borrado, las páginas de la
# versión anterior que gen.nx ya no produce (una receta excluida, un rename)
# se quedarían en static-next/ como huérfanas: el check I las ve, pero más
# vale no crearlas. Se borra ANTES de generar, así lo que quede es exactamente
# lo que el catálogo declara.
echo "[0/4] purga de by-example/ (lo produce gen.nx, ya no se copia)"
rm -rf static-next/by-example static-next/es/by-example

# ── 1. Generador de verdad ──────────────────────────────────────────────
echo "[1/4] nyx gen.nx --out static-next"
if ! nyx gen.nx --out static-next; then
    echo "error: 'nyx gen.nx --out static-next' falló" >&2
    exit 1
fi

# ── 2. install.sh (shim, texto) + logo.png (binario) ────────────────────
# logo.png: la ruta /logo.png sigue REGISTRADA en src/main.nx y read_file()
# de un archivo inexistente devuelve "" — sin esta copia el cutover dejaba
# un 200 image/png de 0 bytes, que es peor que servir el archivo. `cp`
# (nunca write_file de Nyx: no es binary-safe).
echo "[2/4] install.sh (copia textual) + logo.png (copia binaria)"
cp static/install.sh static-next/install.sh
cp static/logo.png static-next/logo.png

# ── 3. Legado: learn/, shared/nyx-design-system.css ─────────────────────
# cp -r (nunca con Nyx: write_file no es binary-safe y este árbol podría
# llevar imágenes u otros binarios el día de mañana — hoy no tiene,
# verificado con
# `find static/learn -type f ! -name '*.html' ! -name '*.css' ! -name '*.js'`).
echo "[3/4] legado: learn/, shared/nyx-design-system.css (cp -r)"
mkdir -p static-next/es static-next/shared
rm -rf static-next/learn static-next/es/learn
cp -r static/learn static-next/learn
cp -r static/es/learn static-next/es/learn
cp static/shared/nyx-design-system.css static-next/shared/nyx-design-system.css

# ── 4. Parche sobre la copia (sed -i, nunca sobre static/) ─────────────
echo "[4/4] parches sobre la copia"

# 4a. Ancla muerta /#products → /docs/ (EN) o /es/docs/ (ES). El nav de learn
# ES usa href="/#products" tal cual (sin /es/), así que en las carpetas ES se
# reemplazan los dos patrones. El texto del enlace de nav (Products/Productos)
# pasa a Docs; los enlaces del footer legado NO cambian de texto, solo de
# destino, para no inventar copy en páginas que este script no reescribe.
# Idempotente por naturaleza: si ya no hay /#products, el sed no matchea nada.
patch_products() {
    local dir="$1" nav_href_old="$2" nav_text_old="$3" new_href="$4"
    find "$dir" -name '*.html' -print0 | while IFS= read -r -d '' f; do
        # anchor de nav completo: href + texto en un solo paso (atómico,
        # así no toca los <a href="...">nyx-kv</a> del footer, que tienen
        # otro texto). Delimitador '|': el patrón lleva '#' y '/', así que
        # '#' como delimitador de sed rompería el parseo.
        sed -i "s|<a href=\"${nav_href_old}\">${nav_text_old}</a>|<a href=\"${new_href}\">Docs</a>|g" "$f"
        # cualquier /#products (o /es/#products) que quede — footer incluido —
        # pasa a apuntar a docs, sin ancla muerta
        sed -i "s|href=\"/#products\"|href=\"${new_href}\"|g; s|href=\"/es/#products\"|href=\"${new_href}\"|g" "$f"
    done
}

patch_products "static-next/learn"    "/#products" "Products"  "/docs/"
patch_products "static-next/es/learn" "/#products" "Productos" "/es/docs/"

# 4b. En TODAS las páginas de «The Nyx Book» (los dos índices Y los 72
# capítulos): elimina la columna de footer "Products"/"Productos" (nyx-kv,
# nyx-serve, nyx-proxy). Aplicarlo sólo a los índices dejaba 216 enlaces
# cuya ETIQUETA es un nombre de producto (la prohibición del plan) y cuyo
# DESTINO es la guía (el sed de 4a los redirige a /docs/) — lo peor de los
# dos mundos. La forma del footer es la misma en índice y capítulo, así que
# el mismo awk sirve para las 74 páginas de cada idioma — awk en vez de
# sed multilínea (mismo criterio que strip_pre en check-content.sh: sed/awk
# no manejan bien un patrón repartido en varias líneas sin volverse
# ilegibles). Estado: guarda la línea de apertura del footer-col; si la
# siguiente es el <h4>Products</h4>/<h4>Productos</h4>, descarta ambas y
# todo hasta el </div> que cierra la columna; si no, la deja pasar tal cual.
# Idempotente: sobre una página ya parcheada no queda ninguna columna así.
strip_products_footer_col() {
    local f="$1"
    awk '
        {
            if (pending != "") {
                if ($0 ~ /<h4>(Products|Productos)<\/h4>/) {
                    skip = 1
                    pending = ""
                    next
                } else {
                    print pending
                    pending = ""
                }
            }
            if (skip) {
                if ($0 ~ /<\/div>/) { skip = 0 }
                next
            }
            if ($0 ~ /<div class="footer-col">/) {
                pending = $0
                next
            }
            print
        }
        END { if (pending != "") print pending }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
for f in static-next/learn/*.html static-next/es/learn/*.html; do
    strip_products_footer_col "$f"
done

# 4c. Banner "libro no mantenido" + noindex, en learn/ y es/learn/.
# CON GUARDA: static/ ya es la copia parcheada de la fase 1, así que sin el
# `grep -q` cada corrida agregaría otro banner y otro <meta robots>. El
# banner va justo después de la apertura de <main class="book-content"> y el
# noindex antes de </head>, cada uno una vez por página (verificado sobre las
# 74 del libro).
patch_book_page() {
    local f="$1" lang="$2"
    if ! grep -q 'class="legacy-banner"' "$f"; then
        if [ "$lang" = "en" ]; then
            sed -i '/<main class="book-content">/a\
<div class="legacy-banner">This book is no longer maintained. The current step-by-step guide lives at <a href="/docs/">/docs/</a>.</div>\
<style>.legacy-banner{background:#fff3cd;border:1px solid #f0c36d;border-radius:6px;padding:.75rem 1rem;margin-bottom:1.5rem;font-size:.9rem}</style>' "$f"
        else
            sed -i '/<main class="book-content">/a\
<div class="legacy-banner">Este libro ya no se mantiene. La guía paso a paso vigente está en <a href="/es/docs/">/es/docs/</a>.</div>\
<style>.legacy-banner{background:#fff3cd;border:1px solid #f0c36d;border-radius:6px;padding:.75rem 1rem;margin-bottom:1.5rem;font-size:.9rem}</style>' "$f"
        fi
    fi
    if ! grep -q 'name="robots"' "$f"; then
        sed -i '/<\/head>/i\    <meta name="robots" content="noindex,follow">' "$f"
    fi
}

for f in static-next/learn/*.html; do
    patch_book_page "$f" "en"
done
for f in static-next/es/learn/*.html; do
    patch_book_page "$f" "es"
done

echo "gen-site: static-next listo (generado + legado parcheado)"
