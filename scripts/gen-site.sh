#!/usr/bin/env bash
# gen-site.sh — orquesta la generación completa de nyxlang.com/static-next.
#
# static-next/ tiene que llevar DOS cosas:
#   1. lo que gen.nx genera de verdad (landing, docs, shared/spec.css, copy.js)
#   2. una copia PARCHEADA del contenido LEGADO que el sitio nuevo sigue
#      sirviendo mientras dure la fase 1 del rediseño: «The Nyx Book»
#      (static/learn/, static/es/learn/), el recetario viejo
#      (static/by-example/, static/es/by-example/), su hoja de estilos
#      (static/shared/nyx-design-system.css) y el shim static/install.sh.
#      Los AGENTS.md que siembra `nyx init` enlazan a mano
#      https://nyxlang.com/by-example/ — esa URL (y las de /learn/) tienen
#      que seguir respondiendo 200 tras el cutover.
#
# El parche (sobre la COPIA, nunca sobre static/) retira el ancla muerta
# /#products, el enlace a Playground, y — solo en «The Nyx Book», no en
# by-example, que sigue siendo una sección viva — agrega un banner
# "este libro ya no se mantiene" + <meta name="robots" content="noindex,follow">
# en cada página.
#
# Idempotente por construcción, no por detección: los directorios LEGADO
# destino se BORRAN y se copian de nuevo desde static/ (la fuente pristina,
# nunca parcheada) en cada corrida, así el parche se aplica siempre sobre
# una copia fresca — nunca sobre una copia ya parcheada. Dos corridas
# seguidas dejan el árbol git-idéntico.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="$REPO_ROOT/nyxlang.com"
cd "$SITE_DIR"

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

# ── 3. Legado: learn/, by-example/, shared/nyx-design-system.css ───────
# cp -r (nunca con Nyx: write_file no es binary-safe y estos árboles
# podrían llevar imágenes u otros binarios el día de mañana — hoy no
# tienen, verificado con
# `find static/learn static/by-example -type f ! -name '*.html' ! -name '*.css' ! -name '*.js'`).
echo "[3/4] legado: learn/, by-example/, shared/nyx-design-system.css (cp -r)"
mkdir -p static-next/es static-next/shared
rm -rf static-next/learn static-next/es/learn static-next/by-example static-next/es/by-example
cp -r static/learn static-next/learn
cp -r static/es/learn static-next/es/learn
cp -r static/by-example static-next/by-example
cp -r static/es/by-example static-next/es/by-example
cp static/shared/nyx-design-system.css static-next/shared/nyx-design-system.css

# ── 4. Parche sobre la copia (sed -i, nunca sobre static/) ─────────────
echo "[4/4] parches sobre la copia"

# 4a. Ancla muerta /#products → /docs/ (EN) o /es/docs/ (ES), en TODO el
# legado (learn Y by-example): el nav de by-example/index.html usa
# href="/es/#products" en ES, pero el nav de learn ES usa href="/#products"
# tal cual (sin /es/) — los dos existen en el árbol real, así que ambos
# patrones se reemplazan en las carpetas ES. El texto del enlace de nav
# (Products/Productos) pasa a Docs; los enlaces del footer legado de
# learn (nyx-kv/nyx-serve/nyx-proxy → /#products) NO cambian de texto,
# solo de destino, para no inventar copy en páginas que T7 no reescribe.
patch_products() {
    local dir="$1" nav_href_old="$2" nav_text_old="$3" new_href="$4"
    find "$dir" -name '*.html' -print0 | while IFS= read -r -d '' f; do
        # anchor de nav completo: href + texto en un solo paso (atómico,
        # así no toca los <a href="...">nyx-kv</a> del footer de learn,
        # que tienen otro texto). Delimitador '|': el patrón lleva '#' y
        # '/', así que '#' como delimitador de sed rompería el parseo.
        sed -i "s|<a href=\"${nav_href_old}\">${nav_text_old}</a>|<a href=\"${new_href}\">Docs</a>|g" "$f"
        # cualquier /#products (o /es/#products) que quede — footer de
        # learn incluido — pasa a apuntar a docs, sin ancla muerta
        sed -i "s|href=\"/#products\"|href=\"${new_href}\"|g; s|href=\"/es/#products\"|href=\"${new_href}\"|g" "$f"
    done
}

patch_products "static-next/learn"        "/#products"    "Products"  "/docs/"
patch_products "static-next/by-example"   "/#products"    "Products"  "/docs/"
patch_products "static-next/es/learn"     "/#products"    "Productos" "/es/docs/"
patch_products "static-next/es/by-example" "/es/#products" "Productos" "/es/docs/"

# 4a-bis. Hallazgo real, no pedido por el plan original pero necesario para
# el rc=0 final: 69 de las 101 páginas de static/es/by-example/ enlazan
# href="/es/learn/book.css", que NUNCA existió (es/learn/ no tiene su
# propio book.css — usa el único /learn/book.css compartido, como hacen
# las otras 32 páginas ES correctas). Es un link roto PREEXISTENTE en el
# legado, no algo que esta copia introduzca — confirmado corriendo
# check-content.sh sobre static/ (el árbol de producción actual) antes de
# tocar nada. Se corrige en la copia, nunca en static/.
find static-next/es/by-example -name '*.html' -print0 | while IFS= read -r -d '' f; do
    sed -i 's|href="/es/learn/book.css"|href="/learn/book.css"|g' "$f"
done

# 4a-ter. Otro hallazgo real preexistente: el «← Previous» de la receta 21
# (traits) enlaza a «20-generics.html», que nunca existió — la receta 20 es
# «20-spawn-channel.html» (19-datetime → 20-spawn-channel → 21-traits →
# 22-trait-bounds, confirmado con los propios enlaces Previous/Next de las
# recetas vecinas). Mismo bug en static/ de producción hoy. Se corrige en
# la copia, nunca en static/.
sed -i 's|href="/by-example/20-generics.html"|href="/by-example/20-spawn-channel.html"|' \
    static-next/by-example/21-traits.html
sed -i 's|href="/es/by-example/20-generics.html"|href="/es/by-example/20-spawn-channel.html"|' \
    static-next/es/by-example/21-traits.html

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

# 4c. Enlace a Playground en el nav de learn (no existe) y en el footer de
# by-example/index.html (EN y ES) — se elimina.
sed -i '/<a href="\/playground\/">Playground<\/a>/d' \
    static-next/by-example/index.html static-next/es/by-example/index.html

# 4d. Banner "libro no mantenido" + noindex, SOLO en learn/ y es/learn/
# (by-example sigue siendo una sección viva hasta la fase 2 — sin banner
# ni noindex ahí). El banner se inserta justo después de la apertura de
# <main class="book-content">, que existe exactamente una vez por página
# en las 74 páginas del libro (verificado); noindex se inserta antes de
# </head>, también una vez por página.
patch_book_page() {
    local f="$1" lang="$2"
    if [ "$lang" = "en" ]; then
        sed -i '/<main class="book-content">/a\
<div class="legacy-banner">This book is no longer maintained. The current step-by-step guide lives at <a href="/docs/">/docs/</a>.</div>\
<style>.legacy-banner{background:#fff3cd;border:1px solid #f0c36d;border-radius:6px;padding:.75rem 1rem;margin-bottom:1.5rem;font-size:.9rem}</style>' "$f"
    else
        sed -i '/<main class="book-content">/a\
<div class="legacy-banner">Este libro ya no se mantiene. La guía paso a paso vigente está en <a href="/es/docs/">/es/docs/</a>.</div>\
<style>.legacy-banner{background:#fff3cd;border:1px solid #f0c36d;border-radius:6px;padding:.75rem 1rem;margin-bottom:1.5rem;font-size:.9rem}</style>' "$f"
    fi
    sed -i '/<\/head>/i\    <meta name="robots" content="noindex,follow">' "$f"
}

for f in static-next/learn/*.html; do
    patch_book_page "$f" "en"
done
for f in static-next/es/learn/*.html; do
    patch_book_page "$f" "es"
done

# 4e. by-example legado, fase 1 (decisión del coordinador de la review final,
# revisable por Ottavio): el recetario se SIGUE sirviendo — los AGENTS.md que
# siembra `nyx init` enlazan a mano /by-example/ y el esquema NN-slug.html —
# pero no se deja indexable la parte que habla de productos, ni se publican
# nombres de producto como títulos de sección.
#
#   (a) noindex,follow en las recetas 71-100 (las de nyx-kv/serve/proxy/queue/
#       db y los full-stack que las usan). `follow` a propósito: las URLs
#       siguen respondiendo 200 y sus enlaces internos siguen valiendo.
#   (b) los tres <h2> con nombre de producto pasan a títulos neutrales.
#
# El CONTENIDO de las recetas se deja como está: la fase 2 las regenera.
for f in static-next/by-example/7[1-9]-*.html \
         static-next/by-example/[89][0-9]-*.html \
         static-next/by-example/100-*.html \
         static-next/es/by-example/7[1-9]-*.html \
         static-next/es/by-example/[89][0-9]-*.html \
         static-next/es/by-example/100-*.html; do
    sed -i '/<\/head>/i\    <meta name="robots" content="noindex,follow">' "$f"
done

sed -i \
    -e 's|<h2>nyx-kv (Key-Value Store)</h2>|<h2>Key-value store</h2>|' \
    -e 's|<h2>nyx-serve (Web Framework)</h2>|<h2>Web framework</h2>|' \
    -e 's|<h2>nyx-proxy (Reverse Proxy)</h2>|<h2>Reverse proxy</h2>|' \
    static-next/by-example/index.html
sed -i \
    -e 's|<h2>nyx-kv (Almacén Clave-Valor)</h2>|<h2>Almacén clave-valor</h2>|' \
    -e 's|<h2>nyx-serve (Framework Web)</h2>|<h2>Framework web</h2>|' \
    -e 's|<h2>nyx-proxy (Proxy Reverso)</h2>|<h2>Proxy inverso</h2>|' \
    static-next/es/by-example/index.html

echo "gen-site: static-next listo (generado + legado parcheado)"
