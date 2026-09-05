#!/usr/bin/env bash
# sync-recipes.sh — sincroniza el recetario de nyxlang.com con el monorepo.
#
# El código de cada receta de /by-example tiene UNA fuente de verdad: el .nx de
# `examples/by-example/` del monorepo del lenguaje, que compila y corre bajo
# `make test-examples`. Este script lo copia byte a byte a
# `nyxlang.com/content/by-example/src/`, de donde el generador lo lee para
# resaltarlo y publicarlo. Nadie edita esas copias: se re-sincronizan.
#
# Bash sin dependencias a propósito (corre en cada build y en cada release; el
# único script del repo que usa python3 es `extract-by-example-prose.sh`, de una
# sola vez, y su cabecera explica por qué).
#
# Uso:
#   bash scripts/sync-recipes.sh            copia las recetas, actualiza la
#                                           versión del sitio y siembra los
#                                           STUB de sidecar que falten
#   bash scripts/sync-recipes.sh --check    no escribe nada; sale 1 si alguna
#                                           copia difiere del monorepo, si falta
#                                           o sobra alguna, o si la versión de
#                                           content/site.toml está desactualizada
#   bash scripts/sync-recipes.sh --drift    MODO EN RETIRO. Inventario de DRIFT:
#                                           por cada receta publicada, si el
#                                           código que mostraba el recetario
#                                           VIEJO ya no coincide con el .nx de
#                                           hoy. Necesita ese árbol viejo, que
#                                           la fase 2 del rediseño reemplaza por
#                                           el recetario generado: cuando no lo
#                                           encuentra, avisa y sale 0 sin tocar
#                                           content/by-example/DRIFT.md, que
#                                           quedó CONGELADO como inventario
#                                           histórico. Se borra junto con el
#                                           modo cuando se limpie la fase 2.
#
# Variables:
#   NYX_MONOREPO   raíz del monorepo del lenguaje (default /home/admin/nyx/lang)
#   OLD_ROOT       raíz del sitio viejo para --drift (default nyxlang.com/static-next)
#
# El alcance sale de `content/by-example/recipes.toml`: se sincroniza lo que
# tiene `excluded = "0"`. Este script NUNCA escribe en el monorepo — lo lee.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
SITE="$ROOT/nyxlang.com"
CONTENT="$SITE/content/by-example"
SRC_DIR="$CONTENT/src"
CATALOG="$CONTENT/recipes.toml"
MONO="${NYX_MONOREPO:-/home/admin/nyx/lang}"
EXAMPLES="$MONO/examples/by-example"
OLD_ROOT="${OLD_ROOT:-$SITE/static-next}"

MODE="sync"
case "${1:-}" in
    "")        MODE="sync" ;;
    --check)   MODE="check" ;;
    --drift)   MODE="drift" ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "sync-recipes: argumento desconocido: $1" >&2; exit 1 ;;
esac

[ -f "$CATALOG" ]   || { echo "sync-recipes: falta $CATALOG" >&2; exit 1; }
[ -d "$EXAMPLES" ]  || { echo "sync-recipes: falta $EXAMPLES (¿NYX_MONOREPO?)" >&2; exit 1; }

# ── alcance ────────────────────────────────────────────────────────────────
# recipes.toml es plano y regular: una tabla [rNN] por receta y un `clave =
# "valor"` por línea. awk basta y evita arrastrar un parser TOML a bash.
# Emite: <slug> <num> <excluded> <sidecar>, en el orden del archivo.
catalog_rows() {
    awk -F' *= *' '
        /^\[/          { if (slug != "") print slug, num, excl, side; slug=""; num=""; excl=""; side="" }
        /^slug *=/     { gsub(/"/, "", $2); slug = $2 }
        /^num *=/      { gsub(/"/, "", $2); num  = $2 }
        /^excluded *=/ { gsub(/"/, "", $2); excl = $2 }
        /^sidecar *=/  { gsub(/"/, "", $2); side = $2 }
        END            { if (slug != "") print slug, num, excl, side }
    ' "$CATALOG"
}

INCLUDED=()
while read -r slug num excl side; do
    [ "$excl" = "0" ] && INCLUDED+=("$slug")
done < <(catalog_rows)

[ ${#INCLUDED[@]} -gt 0 ] || { echo "sync-recipes: recipes.toml no declaró ninguna receta incluida" >&2; exit 1; }

# ── utilidades ─────────────────────────────────────────────────────────────

# Título de relleno para un STUB: «101-file-errors-two-tier» → «File Errors Two Tier».
stub_title() {
    printf '%s' "${1#*-}" | tr '-' ' ' | awk '{ for (i=1; i<=NF; i++) $i = toupper(substr($i,1,1)) substr($i,2); print }'
}

# Las primeras líneas de comentario `//` de un .nx, sin el `//` y sin blancos.
nx_header_lines() {
    awk '/^[[:space:]]*\/\//  { line=$0; sub(/^[[:space:]]*\/\/[[:space:]]?/, "", line); if (line != "") print line; next }
         { exit }' "$1"
}

# Heurística de idioma para repartir las líneas de cabecera de un .nx entre el
# stub EN y el ES. Hace falta porque la convención del monorepo NO es uniforme:
# 101 trae una sola línea, en castellano; 41-70 y 102 traen la inglesa PRIMERO y
# la castellana segunda. Repartir por posición pondría prosa inglesa en el
# sidecar ES. Si la heurística no puede decidir, la línea queda en TODO — que es
# el punto: un stub sin prosa real no se publica.
looks_spanish() {
    printf '%s' "$1" | grep -qiE '[áéíóúñ¿¡]|(^| )(de|del|para|con|los|las|una|que|cuando|desde|sin|por|como|el|la)( |$)'
}

# Una línea de cabecera de un .nx es texto plano, y el blurb va DENTRO de un
# comentario HTML y después dentro de una página. Se escapan `&`, `<` y `>` (la
# cabecera de 101 dice `Result<T, Error>`, que sin escapar se leería como un
# tag), y si aun así queda un `|` o un `--` — que romperían la línea de
# metadatos o el comentario — el blurb pasa a TODO en vez de a algo malformado.
sanitize_blurb() {
    local s
    s="$(printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
    case "$s" in
        *'|'*|*'--'*) printf 'TODO' ;;
        *) printf '%s' "$s" ;;
    esac
}

# ── modo drift ─────────────────────────────────────────────────────────────
# Código publicado en el HTML VIEJO (el <pre> bajo <h2>Code</h2>), des-escapado
# y sin los <span> del resaltado, para compararlo con el .nx de hoy.
old_published_code() {
    awk '
        /<h2>Code<\/h2>/ { seen = 1; next }
        seen && !inb && /<pre><code>/ {
            sub(/^.*<pre><code>/, "")
            inb = 1
            if ($0 ~ /<\/code><\/pre>/) { sub(/<\/code><\/pre>.*$/, ""); print; exit }
            print; next
        }
        inb {
            if ($0 ~ /<\/code><\/pre>/) { sub(/<\/code><\/pre>.*$/, ""); if ($0 != "") print; exit }
            print
        }
    ' "$1" | sed -e 's/<span[^>]*>//g' \
                 -e 's|</span>||g' \
                 -e 's/&lt;/</g' \
                 -e 's/&gt;/>/g' \
                 -e 's/&quot;/"/g' \
                 -e "s/&#x27;/'/g" \
                 -e "s/&#39;/'/g" \
                 -e 's/&amp;/\&/g'
}

if [ "$MODE" = "drift" ]; then
    # El modo compara contra el recetario VIEJO (páginas con <h2>Code</h2>
    # escritas a mano). Desde la fase 2 el árbol publicado es el generado, que
    # no tiene ese marcador: sin esta guarda, --drift informaría «receta nueva»
    # para las 69 y sobreescribiría DRIFT.md con un inventario falso. Avisar y
    # salir 0 es lo correcto: no hay nada que medir, y no es un error.
    probe="$OLD_ROOT/by-example/01-hello-world.html"
    if [ ! -f "$probe" ] || ! grep -q '<h2>Code</h2>' "$probe"; then
        echo "sync-recipes --drift: no hay recetario VIEJO en $OLD_ROOT (páginas con <h2>Code</h2>)."
        echo "  El modo compara contra el sitio anterior a la fase 2 y se retira con él."
        echo "  content/by-example/DRIFT.md queda como está: es un inventario histórico congelado."
        echo "  Para medir contra otro árbol: OLD_ROOT=<ruta> bash scripts/sync-recipes.sh --drift"
        exit 0
    fi
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    out="$CONTENT/DRIFT.md"
    drifted=0; equal=0; nopage=0; total=0
    rows=""
    for slug in "${INCLUDED[@]}"; do
        total=$((total + 1))
        page="$OLD_ROOT/by-example/$slug.html"
        nx="$EXAMPLES/$slug.nx"
        if [ ! -f "$page" ]; then
            nopage=$((nopage + 1))
            rows="$rows| \`$slug\` | — | receta nueva: no existe en el recetario viejo |"$'\n'
            continue
        fi
        old_published_code "$page" > "$tmp"
        if diff -q "$tmp" "$nx" >/dev/null 2>&1; then
            equal=$((equal + 1))
            continue
        fi
        drifted=$((drifted + 1))
        add=$(diff "$tmp" "$nx" | grep -c '^>')
        del=$(diff "$tmp" "$nx" | grep -c '^<')
        oldn=$(wc -l < "$tmp"); newn=$(wc -l < "$nx")
        rows="$rows| \`$slug\` | $oldn → $newn | +$add / -$del |"$'\n'
    done

    {
        echo "# DRIFT del recetario — código publicado vs. \`.nx\` del monorepo"
        echo
        echo "Generado por \`bash scripts/sync-recipes.sh --drift\`. NO se edita a mano."
        echo
        echo "Compara, por cada receta publicada, el código que muestra el recetario VIEJO"
        echo "(\`$(basename "$OLD_ROOT")/by-example/<slug>.html\`, des-escapado y sin los \`<span>\` del"
        echo "resaltado) contra \`examples/by-example/<slug>.nx\` del monorepo, que es la fuente de"
        echo "verdad y lo que se publica de ahora en más."
        echo
        echo "Que una receta figure acá significa que **la prosa del sidecar puede estar describiendo"
        echo "código que ya no existe**: es la lista de trabajo de la revisión de prosa (T10). Que NO"
        echo "figure significa que el código publicado seguía siendo idéntico al del monorepo."
        echo
        echo "| receta | líneas (publicado → \`.nx\`) | diferencia |"
        echo "|---|---|---|"
        printf '%s' "$rows"
        echo
        echo "- recetas publicadas: $total"
        echo "- con drift: $drifted"
        echo "- idénticas: $equal"
        echo "- sin página vieja (recetas nuevas): $nopage"
    } > "$out"

    cat "$out"
    exit 0
fi

# ── modos sync / check ─────────────────────────────────────────────────────
findings=0
copied=0; same=0; stubs=0

mkdir -p "$SRC_DIR"

for slug in "${INCLUDED[@]}"; do
    nx="$EXAMPLES/$slug.nx"
    dest="$SRC_DIR/$slug.nx"
    if [ ! -f "$nx" ]; then
        echo "  ✗ $slug: no existe $nx en el monorepo"
        findings=$((findings + 1))
        continue
    fi
    if cmp -s "$nx" "$dest" 2>/dev/null; then
        same=$((same + 1))
        continue
    fi
    if [ "$MODE" = "check" ]; then
        if [ ! -f "$dest" ]; then
            echo "  ✗ $slug: falta content/by-example/src/$slug.nx"
        else
            add=$(diff "$dest" "$nx" | grep -c '^>')
            del=$(diff "$dest" "$nx" | grep -c '^<')
            echo "  ✗ $slug: la copia difiere del monorepo (+$add / -$del)"
        fi
        findings=$((findings + 1))
    else
        cp "$nx" "$dest"
        copied=$((copied + 1))
    fi
done

# Copias huérfanas: un rename o una exclusión dejan un .nx que ya nadie publica.
for f in "$SRC_DIR"/*.nx; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .nx)"
    keep=0
    for slug in "${INCLUDED[@]}"; do [ "$slug" = "$b" ] && keep=1 && break; done
    if [ "$keep" = "0" ]; then
        if [ "$MODE" = "check" ]; then
            echo "  ✗ $b: sobra en content/by-example/src/ (no está incluida en recipes.toml)"
            findings=$((findings + 1))
        else
            rm -f "$f"
            echo "  · $b: copia huérfana borrada (ya no está incluida en recipes.toml)"
        fi
    fi
done

# ── versión del sitio ──────────────────────────────────────────────────────
site_toml="$SITE/content/site.toml"
mono_version="$(tr -d ' \t\n\r' < "$MONO/VERSION" 2>/dev/null)"
site_version="$(awk -F'"' '/^version *=/ { print $2; exit }' "$site_toml")"
if [ -z "$mono_version" ]; then
    echo "  ✗ no se pudo leer $MONO/VERSION"
    findings=$((findings + 1))
elif [ "$mono_version" != "$site_version" ]; then
    if [ "$MODE" = "check" ]; then
        echo "  ✗ content/site.toml: version = $site_version, el monorepo dice $mono_version"
        findings=$((findings + 1))
    else
        # Se reescribe SOLO la línea de `version`; el resto del archivo (y sus
        # comentarios) queda intacto.
        tmp="$(mktemp)"
        awk -v v="$mono_version" '/^version *=/ && !done { print "version = \"" v "\""; done=1; next } { print }' "$site_toml" > "$tmp"
        mv "$tmp" "$site_toml"
        echo "  · content/site.toml: version $site_version → $mono_version"
    fi
fi

# ── STUB de sidecar para recetas sin prosa heredada ────────────────────────
# Una receta nueva del monorepo entra al catálogo con `sidecar = "0"` y no tiene
# página vieja de donde sacar prosa. En vez de publicarla muda (o, peor, con
# prosa inventada), se siembra un STUB: el título es el slug capitalizado, el
# blurb sale de la línea de cabecera del propio .nx en el idioma que
# corresponda, y todo lo demás dice TODO. El check G de check-content.sh
# convierte cada TODO en un ✗, así que el sitio NO pasa su guardia hasta que
# alguien escriba la prosa de verdad.
if [ "$MODE" = "sync" ]; then
    for slug in "${INCLUDED[@]}"; do
        en="$CONTENT/$slug.en.html"
        es="$CONTENT/$slug.es.html"
        [ -f "$en" ] && [ -f "$es" ] && continue
        nx="$EXAMPLES/$slug.nx"
        [ -f "$nx" ] || continue

        title="$(stub_title "$slug")"
        blurb_es="TODO"; blurb_en="TODO"
        while IFS= read -r line; do
            if looks_spanish "$line"; then
                [ "$blurb_es" = "TODO" ] && blurb_es="$(sanitize_blurb "$line")"
            else
                [ "$blurb_en" = "TODO" ] && blurb_en="$(sanitize_blurb "$line")"
            fi
        done < <(nx_header_lines "$nx" | head -2)

        for lang in en es; do
            target="$CONTENT/$slug.$lang.html"
            [ -f "$target" ] && continue
            if [ "$lang" = "en" ]; then
                blurb="$blurb_en"
                intro="TODO — write the introduction for this recipe."
                expl="TODO — write the explanation for this recipe."
            else
                blurb="$blurb_es"
                intro="TODO — falta escribir la introducción de esta receta."
                expl="TODO — falta escribir la explicación de esta receta."
            fi
            {
                echo "<!-- title: $title | blurb: $blurb -->"
                echo '<section data-part="intro">'
                echo "<p>$intro</p>"
                echo '</section>'
                echo '<section data-part="output">'
                echo 'TODO'
                echo '</section>'
                echo '<section data-part="explanation">'
                echo "<p>$expl</p>"
                echo '</section>'
            } > "$target"
            stubs=$((stubs + 1))
            echo "  · $slug [$lang]: STUB de sidecar sembrado (queda con TODO a propósito)"
        done
    done
fi

# ── resumen ────────────────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
    if [ "$findings" -gt 0 ]; then
        echo "sync-recipes --check: $findings hallazgo(s) — hay que correr \`bash scripts/sync-recipes.sh\`"
        exit 1
    fi
    echo "sync-recipes --check: ${#INCLUDED[@]} receta(s) al día con $MONO (version $site_version)"
    exit 0
fi

echo "sync-recipes: ${#INCLUDED[@]} receta(s) incluidas — $copied copiada(s), $same sin cambios, $stubs stub(s) de sidecar"
[ "$findings" -gt 0 ] && exit 1
exit 0
