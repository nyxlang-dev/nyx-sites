#!/usr/bin/env bash
# check-content.sh — guardias del contenido PUBLICADO de nyxlang.com.
#
# Uso: bash scripts/check-content.sh [ROOT]     (default: nyxlang.com/static-next)
#
# Corre desde la raíz del repo (o de cualquier lado: se reubica solo). Sirve
# tanto sobre el árbol NUEVO generado por gen.nx (nyxlang.com/static-next)
# como sobre el árbol VIEJO escrito a mano (nyxlang.com/static) — así se
# puede correr el mismo instrumento antes Y después del cutover que la T7 va
# a hacer (intercambiar static-next por static).
#
# NO corre scripts/check-doc-blocks.sh (T4): ese script COMPILA cada bloque
# de Nyx de la guía /docs, una verificación cara (invoca al compilador N
# veces) y de otra naturaleza (¿el código anda?, no ¿el contenido es
# publicable?). Queda aparte, en `make gen-docblocks`. Wiring recomendado:
# `make gen-docblocks && make check-content` en CI/pre-release — dos redes
# independientes, cada una responsable de una sola cosa.
#
# Checks (cada uno imprime ✓/✗ por hallazgo + un resumen con contador; sale 1
# si hubo algún ✗ en el árbol real):
#
#   A. Denylist de productos (case-insensitive) sobre ROOT menos el LEGADO
#      (ver `is_legacy_path()` más abajo). Incluye además los nombres de
#      herramientas de IA (claude/cursor/copilot) FUERA del literal
#      `--agent=claude,cursor,copilot`, que es la única excepción — esta
#      segunda parte, sólo sobre .html del legado excluido.
#   B. Métricas/benchmarks inventados. Solo sobre *.html fuera del LEGADO
#      (una cifra de rendimiento es copy, no CSS/JS) y con el contenido de
#      <pre>...</pre> quitado antes de buscar — una transcripción real de
#      `nyx test` dice «(2 tests)» y una transición CSS dice «120ms»;
#      ninguna de las dos es la clase de afirmación de marketing que este
#      check persigue. Ver nota en `strip_pre()`.
#   C. Plataformas no soportadas, excepto dentro del LEGADO.
#   D. Identidad vieja / recursos externos de la landing anterior, excepto
#      dentro del LEGADO.
#   E. Anclas muertas (#products) en TODO ROOT, LEGADO incluido — la T7 las
#      parchea; hasta entonces cualquier aparición es una regresión real.
#   F. Enlaces internos: cada href="/…" y src="/…" de TODOS los .html de
#      ROOT (LEGADO incluido — la T7 parchea sus anclas) tiene que resolver
#      a un archivo bajo ROOT (directorio → index.html); cada href="#…"
#      tiene que tener su id en la MISMA página. Los https:// no se
#      verifican (sin red).
#   G. Paridad EN/ES: mismo conjunto de rutas relativas bajo ROOT/ y
#      ROOT/es/ (excluyendo el LEGADO, shared/ e install.sh); por cada par
#      presente en los dos lados, misma cantidad de <pre y de <h2; mismas
#      claves en content/i18n/{en,es}.toml; por cada content/**/*.en.html
#      existe el .es.html; y ningún content/**/*.html tiene prosa pendiente
#      (la palabra TODO, que es lo que siembran los STUB de sidecar de
#      scripts/sync-recipes.sh) — nada se publica con prosa inventada ni muda.
#      Un archivo que existe en UN SOLO lado (p.ej. mientras static/docs/
#      todavía no tiene su par en static/es/docs/, antes del cutover) se
#      reporta como ⚠ aviso, no como ✗: la paridad ESTRUCTURAL (<pre>/<h2>/
#      claves) solo se exige sobre lo que ya existe en los dos lados — así
#      el check no bloquea un rollout incremental, solo lo hace visible.
#   H. Español neutro: denylist de voseo/vosotros sobre ROOT/es/ (excepto
#      learn/) y sobre content/**/*.es.*.
#   I. Salida al día: `nyx gen.nx --out <basename de ROOT> --check` (compara
#      byte a byte lo que gen.nx SABE que produce) + comparación del LISTADO
#      de archivos entre ROOT y una generación fresca en un temporal (caza
#      huérfanos que --check no ve, porque --check no mira archivos de más
#      en <out>). Si `nyx` no está en PATH da ✗ (fix round 2: esta guardia
#      corre en máquinas con la toolchain, que falte no es un pase gratis).
#      Se salta con ⚠ solo si ROOT no tiene un gen.nx al lado (el fixture
#      sintético del autotest, que no pretende ser un sitio generado).
#   J. Versión: `nyx --version` (el toolchain del PATH) tiene que coincidir
#      con `version` de content/site.toml y con TODO literal X.Y.Z bajo
#      content/docs/, content/landing/ y content/by-example/. Un número
#      punteado más largo (una IPv4 como 127.0.0.1, que el recetario publica)
#      NO cuenta como literal de versión — ver `version_literals`. Sin esto, el próximo bump del
#      lenguaje deja la landing con un sello viejo y la guía enseñando
#      `nyx --version → nyx 0.31.0` — exactamente el defecto que este
#      rediseño existe para reparar. Un literal que NO es la versión del
#      toolchain (p.ej. el `0.1.0` del proyecto de ejemplo en una
#      transcripción) se exime con un comentario HTML:
#        <!-- not-a-version -->          exime la línea donde está
#        <!-- not-a-version: 0.1.0 -->   exime ESE literal en todo el archivo
#      La segunda forma existe porque un comentario DENTRO de un <pre> no
#      sirve: el resaltador escapa el `<` antes de que strip_html_comments
#      corra, y el comentario se vería como texto en la página. Va en la
#      primera línea del fragmento, fuera de todo <pre>.
#   K. HTML publicado sin agujeros: ningún <title></title>, ningún
#      content="" en la meta description, ningún <h1>/<h2> vacío y ningún
#      `{{` residual FUERA de <pre> y de <code>, todo fuera del LEGADO.
#      La excepción de <pre>/<code> es la convención de la fase 2: ahí `{{`
#      es contenido (la receta 102 enseña std/template y muestra su sintaxis
#      en el código y en la explicación), no una interpolación sin resolver.
#      Una clave i18n ausente interpola ""
#      en silencio (documentado en src/gen/render.nx:18) y title_key/desc_key
#      se resuelven con get_or(..., ""), así que un `stem` mal escrito
#      publica un <title>/<h1> vacío en los DOS idiomas sin que G (que
#      compara EN contra ES, no contra un valor esperado) diga nada.
#
#   L. El recetario publicado no tiene drift con el monorepo:
#      `scripts/sync-recipes.sh --check`. Es la única guardia que mira FUERA
#      del repo (necesita examples/by-example/ del monorepo del lenguaje); si
#      no lo encuentra, avisa con ⚠ y no falla. Corre además
#      `sync-recipes.sh --check-mirror` y lo reporta como AVISO: los enlaces
#      «Source →» del recetario apuntan al MIRROR PÚBLICO, que se sincroniza
#      en el paso 8 del runbook (después del swap), así que una diferencia ahí
#      no es un fallo del contenido — pero sí es la clase de cosa que se
#      publica sin que nadie la mire.
#
#   QUÉ MIRA CADA CHECK. Sobre el ÁRBOL PUBLICADO (ROOT): A, B, C, D, E, F,
#   K y la primera mitad de G (paridad de rutas y de <pre>/<h2> entre ROOT/ y
#   ROOT/es/). Sobre content/ del sitio: J (literales de versión), L (drift
#   del recetario), la segunda mitad de G (claves de i18n, pares
#   *.en.html/*.es.html y prosa pendiente) y H, que mira las DOS cosas
#   (ROOT/es/ y content/**/*.es.*). I compara ROOT contra una generación
#   fresca, o sea las dos puntas a la vez. `content/` incluye el recetario:
#   content/by-example/ son sidecars de prosa, y se juzgan como contenido.
#
#   Autotest (control positivo): corre PRIMERO, siempre. Crea un SITIO
#      temporal (content/ + static-next/) con errores plantados a propósito
#      que disparan A, B, C, E, F, G, J, K y L (L con su propio catálogo, su
#      copia de receta y un "monorepo" falso cuyo .nx difiere en un byte); si
#      alguno no lo detecta, el script se declara ROTO y sale 2 antes de tocar
#      el árbol real — un guardia que no ve sus propios controles positivos no
#      prueba nada estando en verde. B, J, K y L exigen un número EXACTO de
#      hallazgos, no «≥1»: así el control no lo puede dar por bueno un error de
#      otra clase plantado en la misma página. D y H comparten scan_denylist
#      con A y C (cobertura indirecta); I queda sin control positivo (ficha
#      [BAJA] en el TASKS.md del monorepo).
#
#   Piso mínimo (corre después del autotest, antes de evaluar A-I sobre
#   ROOT, sin depender de `nyx` ni de `gen.nx`): ROOT/index.html y
#   ROOT/es/index.html tienen que existir, y tiene que haber al menos
#   $MIN_HTML_FILES archivos .html fuera de learn/ (el legado PERMANENTE,
#   nunca enlazado — un legado MÁS ANGOSTO que el de A-D/G/H/I, que además
#   excluye by-example/ de forma transitoria: por volumen, by-example
#   cuenta como material real aunque esos checks no lo escaneen todavía;
#   ver el comentario en `check_floor`). Sin esto un ROOT vacío o a medio
#   generar daba "✓ 0 coincidencias" en A-D/F/H (nada que escanear no es
#   lo mismo que nada sospechoso) — rc=0 sobre la nada. Si falta, imprime
#   «GUARDIA SIN MATERIAL» y sale 2, mismo trato que el autotest roto.
#
# LEGADO (PERMANENTE, lo que queda tras la fase 2): «The Nyx Book»
# (learn/, es/learn/) y su hoja shared/nyx-design-system.css, que
# gen-site.sh copia tal cual de static/ y que nadie reescribe. A, B, C, D,
# H e I no lo escanean (via legacy_prune_args) — sería ruido sobre
# contenido que ya no se mantiene y que gen.nx no produce. E (anclas
# muertas) y F (enlaces internos) SÍ lo escanean completo: son regresiones
# reales incluso en contenido legado, y gen-site.sh es quien parchea sus
# anclas. G lo excluye igual que a `shared/`: no declara paridad EN/ES bajo
# este esquema. I suma además install.sh y logo.png, aparte de
# legacy_prune_args: A-D ya los descartan por extensión (.sh/.png no son
# .html/.css/.js), pero el listado de I no filtra por extensión y gen.nx
# tampoco genera esos dos archivos, que copia gen-site.sh.
#
# by-example/ y es/by-example/ YA NO SON LEGADO (fase 2): el recetario lo
# genera gen.nx desde content/by-example/, así que TODOS los checks lo
# miran. Sus 138 páginas ya no cargan Google Fonts.
#
# DEUDA CONOCIDA que queda: las 74 páginas de learn/ y es/learn/ SÍ cargan
# Google Fonts (fonts.googleapis / fonts.gstatic). El check D lo detectaría,
# pero learn/ está exento, así que el sitio todavía no cumple el criterio
# del plan «ninguna página con Google Fonts» para ese material. Se salda el
# día que el libro se regenere o se retire; ahí learn/ sale de esta lista.
#
# set -u sin pipefail (grep sin coincidencias sale 1, y con -e o pipefail
# eso mataría el script en la primera búsqueda vacía — la misma regla que
# scripts/testing/run_templates_parity.sh del monorepo del lenguaje).
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ROOT="${1:-nyxlang.com/static-next}"
ROOT="${ROOT%/}"
SITE_DIR="$(dirname "$ROOT")"

if [ ! -d "$ROOT" ]; then
    echo "error: « $ROOT » no existe (¿corriste 'make gen'?)" >&2
    exit 2
fi

# ── Denylist de español neutro (H) ───────────────────────────────────────
# Copiada TAL CUAL de la variable DENY_RE de
# /home/admin/nyx/lang/scripts/testing/run_templates_parity.sh (monorepo del
# lenguaje, no este repo) — no se importa por ruta porque nyx-sites es un
# repo independiente sin dependencia de ese monorepo. Si esa lista crece,
# esta copia se queda atrás hasta que alguien la sincronice a mano.
VOSEO_RE='\b(sos|tenés|podés|querés|sabés|hacé|seguí|ofrecé|leé|probá|declará|borrá|usá|corré|mirá|fijate|acordate|vos|vosotros|tenéis|podéis|sabéis|ejecutá|agregá|revisá|instalá|escribí|elegí|poné|dejá|decí|tené|asegurate|necesitás|debés|hacés|abrí|cambiá|verificá)\b'

DENY_PRODUCTS_RE='nyx-kv|nyxkv|nyx-serve|nyx-proxy|nyx-edit|nyx-db|nyx-queue|nyx-shell|\bgateway\b|playground|serve\.nyxlang|proxy\.nyxlang|edit\.nyxlang|nyxkv\.com'
AI_TOOLS_RE='\bclaude\b|cursor|copilot'
# El porcentaje comparativo entró en la fase 2 (review final): «~30% smaller
# than JSON» / «~30% más liviana que JSON» vivía en seis superficies
# publicadas de 44-msgpack y este regex no lo veía — B daba verde sobre una
# cifra de rendimiento que nada mide. Dos formas: el porcentaje seguido de un
# comparativo (EN o ES) y el «~N%» aproximado, que ya es una medición sin
# medición aunque no traiga comparativo detrás.
METRICS_RE='req/s|ops/s|[0-9][0-9.,]*\s*(ms|µs|x faster|× faster|veces más rápido)|benchmark|faster than|más rápido que|[0-9]+ (recipes|recetas|tests|seconds|segundos)|[0-9]+ ?% ?(smaller|larger|faster|slower|less|more|más|menos|mayor|menor)|~[0-9]+ ?%'
PLATFORMS_RE='macOS|mac os|Windows|brew install|WSL'
IDENTITY_RE='Ephemeris|Fraunces|fonts\.googleapis|fonts\.gstatic|logo\.png'

# ── Impresión y contadores ───────────────────────────────────────────────
# Cada check_* deja su cantidad de hallazgos en CHECK_LAST_FAILS al volver;
# quien lo llama decide si eso suma al TOTAL_FAIL real o si es del autotest
# (que produce ✗ a propósito y no debe contaminar el resultado del árbol).
print_ok()   { printf '  \xe2\x9c\x93 %s\n' "$1"; }
print_bad()  { printf '  \xe2\x9c\x97 %s\n' "$1"; }
print_warn() { printf '  \xe2\x9a\xa0 %s\n' "$1"; }
banner() { printf -- '\n── %s ──\n' "$1"; }

CHECK_LAST_FAILS=0
# Los ⚠ de G (rollout incremental) no son fallos, pero el control positivo
# del autotest necesita poder verlos: check_g los deja acá.
CHECK_LAST_WARNS=0
# Salida cruda del último check que delega en otro script (hoy sólo L). El
# control positivo de L no puede conformarse con «hubo ≥1 hallazgo»: eso lo
# cumple también un L que ignore el $root recibido y evalúe el content/ real
# contra el monorepo falso. Mirando el TEXTO se comprueba que evaluó el
# sitio-fixture y no otro.
CHECK_LAST_LOG=""

# Lista archivos bajo $1=root con los predicados -name que sigan ($2, $3…),
# excluyendo el LEGADO (ver comentario arriba de `set -u`). Usada por A, B,
# C y D — no por E/F (que sí escanean el legado) ni por G (que tiene su
# propia lista de exclusiones, learn/shared/install.sh/by-example, porque
# compara EN contra ES en vez de listar un solo lado).
# Predicados -not -path del LEGADO (learn/, es/learn/ y
# shared/nyx-design-system.css) para un $root dado. Una sola función que
# find_nolegacy (A-D), check_h y check_i reutilizan tal cual — no duplicar
# esta lista de rutas en más de un lugar.
#
# by-example/ y es/by-example/ SALIERON de esta lista en la fase 2: el
# recetario lo genera gen.nx desde content/by-example/, así que todos los
# checks lo miran como contenido propio (y el check I lo compara contra la
# generación fresca, en vez de tratarlo como huérfano).
legacy_prune_args() {
    local root="$1"
    LEGACY_PRUNE=(
        -not -path "$root/learn/*"
        -not -path "$root/es/learn/*"
        -not -path "$root/shared/nyx-design-system.css"
    )
}

find_nolegacy() {
    local root="$1"; shift
    legacy_prune_args "$root"
    find "$root" -type f "$@" "${LEGACY_PRUNE[@]}" 2>/dev/null | sort
}

# Escanea $files (lista separada por líneas) con el regex $2 y reporta cada
# coincidencia como ✗ etiquetada $1. $files vacío = 0 archivos, 0 hallazgos.
#
# Un archivo por vez, con "$f" citado (nunca $files sin comillas pasado
# entero a grep): un nombre con espacios se partía en silencio en varios
# argumentos de find/grep y podía saltearse contenido sin avisar. `grep -H`
# fuerza el prefijo de archivo aunque sea una sola invocación por archivo.
scan_denylist() {
    local label="$1" regex="$2" files="$3"
    local n=0
    if [ -n "$files" ]; then
        local f
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            while IFS= read -r hit; do
                [ -z "$hit" ] && continue
                print_bad "[$label] $hit"
                n=$((n + 1))
            done < <(grep -HniE -- "$regex" "$f" 2>/dev/null)
        done <<EOF
$files
EOF
    fi
    if [ "$n" -eq 0 ]; then
        print_ok "[$label] 0 coincidencias"
    else
        print_bad "[$label] $n coincidencia(s)"
    fi
    CHECK_LAST_FAILS=$n
}

# Quita el contenido de <pre>...</pre> (abre y cierra en cualquier línea,
# tags balanceados dentro de la misma línea o repartidos en varias) — usado
# SOLO por el check B. Máquina de estados simple con index()/substr(), sin
# regex multilínea (que ni sed ni awk hacen bien sin volverse ilegibles).
strip_pre() {
    awk '
        {
            line = $0
            out = ""
            while (length(line) > 0) {
                if (!inpre) {
                    i = index(line, "<pre")
                    if (i == 0) { out = out line; line = ""; break }
                    out = out substr(line, 1, i - 1)
                    line = substr(line, i)
                    gt = index(line, ">")
                    if (gt == 0) { inpre = 1; line = ""; break }
                    line = substr(line, gt + 1)
                    inpre = 1
                } else {
                    j = index(line, "</pre>")
                    if (j == 0) { line = ""; break }
                    line = substr(line, j + 6)
                    inpre = 0
                }
            }
            print out
        }
    ' "$1"
}

# Gemelo de strip_pre para <code>…</code>, pero como FILTRO de stdin (se
# encadena después de strip_pre). Usado SOLO por el sub-check de `{{` de K.
strip_code() {
    awk '
        {
            line = $0
            out = ""
            while (length(line) > 0) {
                if (!incode) {
                    i = index(line, "<code")
                    if (i == 0) { out = out line; line = ""; break }
                    out = out substr(line, 1, i - 1)
                    line = substr(line, i)
                    gt = index(line, ">")
                    if (gt == 0) { incode = 1; line = ""; break }
                    line = substr(line, gt + 1)
                    incode = 1
                } else {
                    j = index(line, "</code>")
                    if (j == 0) { line = ""; break }
                    line = substr(line, j + 7)
                    incode = 0
                }
            }
            print out
        }
    '
}

# ── A. Denylist de productos + herramientas de IA fuera de --agent= ─────
check_a() {
    local root="$1"
    local files html_files n1 n2
    files=$(find_nolegacy "$root" \( -name '*.html' -o -name '*.css' -o -name '*.js' \))

    scan_denylist "A" "$DENY_PRODUCTS_RE" "$files"
    n1=$CHECK_LAST_FAILS

    # Sólo .html: "cursor" es una propiedad CSS legítima (cursor: pointer) y
    # escanear .css/.js ahí da falsos positivos que nada tienen que ver con
    # la herramienta de IA. El nombre de una herramienta es texto de página,
    # no sintaxis de estilos.
    html_files=$(find_nolegacy "$root" -name '*.html')
    n2=0
    if [ -n "$html_files" ]; then
        local hf
        while IFS= read -r hf; do
            [ -z "$hf" ] && continue
            while IFS= read -r hit; do
                [ -z "$hit" ] && continue
                case "$hit" in
                    *--agent=*) continue ;;
                    *)
                        print_bad "[A] herramienta de IA fuera de --agent=: $hit"
                        n2=$((n2 + 1))
                        ;;
                esac
            done < <(grep -HniE -- "$AI_TOOLS_RE" "$hf" 2>/dev/null)
        done <<EOF
$html_files
EOF
    fi
    if [ "$n2" -eq 0 ]; then
        print_ok "[A] 0 nombres de herramienta de IA fuera de --agent="
    else
        print_bad "[A] $n2 nombre(s) de herramienta de IA fuera de --agent="
    fi

    CHECK_LAST_FAILS=$((n1 + n2))
}

# ── B. Métricas/benchmarks inventados ────────────────────────────────────
check_b() {
    local root="$1"
    local files n=0
    files=$(find_nolegacy "$root" -name '*.html')
    if [ -n "$files" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            while IFS= read -r hit; do
                [ -z "$hit" ] && continue
                print_bad "[B] $f:$hit"
                n=$((n + 1))
            done < <(strip_pre "$f" | grep -niE -- "$METRICS_RE" 2>/dev/null)
        done <<EOF
$files
EOF
    fi
    if [ "$n" -eq 0 ]; then
        print_ok "[B] 0 coincidencias (fuera de bloques <pre>)"
    else
        print_bad "[B] $n coincidencia(s)"
    fi
    CHECK_LAST_FAILS=$n
}

# ── C. Plataformas no soportadas (excepto el LEGADO) ─────────────────────
check_c() {
    local root="$1" files
    files=$(find_nolegacy "$root" \( -name '*.html' -o -name '*.css' -o -name '*.js' \))
    scan_denylist "C" "$PLATFORMS_RE" "$files"
}

# ── D. Identidad vieja / recursos externos (excepto el LEGADO) ──────────
check_d() {
    local root="$1" files
    files=$(find_nolegacy "$root" \( -name '*.html' -o -name '*.css' -o -name '*.js' \))
    scan_denylist "D" "$IDENTITY_RE" "$files"
}

# ── E. Anclas muertas (#products), TODO ROOT incluido learn/ ────────────
check_e() {
    local root="$1" files
    files=$(find "$root" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' \) 2>/dev/null | sort)
    scan_denylist "E" '#products' "$files"
}

# ── F. Enlaces internos (TODO ROOT, LEGADO incluido) ─────────────────────
check_f() {
    local root="$1"
    local files n=0
    files=$(find "$root" -type f -name '*.html' 2>/dev/null | sort)
    [ -z "$files" ] && { print_ok "[F] 0 archivos que revisar"; CHECK_LAST_FAILS=0; return; }

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        while IFS= read -r link; do
            [ -z "$link" ] && continue
            case "$link" in
                http://*|https://*|mailto:*|tel:*)
                    ;;
                \#*)
                    id="${link#\#}"
                    if [ -n "$id" ] && ! grep -q "id=\"$id\"" "$f" 2>/dev/null; then
                        print_bad "[F] $f: ancla «#$id» sin id= en la misma página"
                        n=$((n + 1))
                    fi
                    ;;
                /*)
                    path="${link%%#*}"
                    path="${path%%\?*}"
                    target="$root$path"
                    if [ -d "$target" ]; then
                        target="${target%/}/index.html"
                    fi
                    if [ ! -f "$target" ]; then
                        print_bad "[F] $f: enlace roto « $link » (no existe $target)"
                        n=$((n + 1))
                    fi
                    ;;
                *)
                    ;;
            esac
        done < <(grep -oE '(href|src)="[^"]*"' "$f" 2>/dev/null | sed -E 's/^(href|src)="//; s/"$//')
    done <<EOF
$files
EOF

    if [ "$n" -eq 0 ]; then
        print_ok "[F] 0 enlaces rotos / anclas sin id"
    else
        print_bad "[F] $n enlace(s)/ancla(s) rotos"
    fi
    CHECK_LAST_FAILS=$n
}

# ── G. Paridad EN/ES ──────────────────────────────────────────────────────
# site_dir se deriva de $root (igual que check_j, y no de la global SITE_DIR)
# para que el autotest mire el content/ de SU sitio-fixture y no el real: con
# la global, el control positivo leía los diccionarios y los sidecars de
# verdad y mezclaba sus hallazgos con los plantados.
check_g() {
    local root="$1"
    local site_dir; site_dir="$(dirname "$root")"
    local fails=0 warns=0

    if [ -d "$root/es" ]; then
        local en_files es_files only_en only_es common
        en_files=$(find "$root" -type f \
            -not -path "$root/es/*" -not -path "$root/learn/*" \
            -not -path "$root/shared/*" \
            -not -name "install.sh" -not -name "logo.png" 2>/dev/null \
            | sed "s#^$root/##" | sort)
        es_files=$(find "$root/es" -type f \
            -not -path "$root/es/learn/*" 2>/dev/null \
            | sed "s#^$root/es/##" | sort)

        only_en=$(comm -23 <(printf '%s\n' "$en_files") <(printf '%s\n' "$es_files"))
        only_es=$(comm -13 <(printf '%s\n' "$en_files") <(printf '%s\n' "$es_files"))

        if [ -n "$only_en" ]; then
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                print_warn "[G] solo en EN, falta el par ES todavía: $rel"
                warns=$((warns + 1))
            done <<EOF2
$only_en
EOF2
        fi
        if [ -n "$only_es" ]; then
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                print_warn "[G] solo en ES, falta el par EN todavía: $rel"
                warns=$((warns + 1))
            done <<EOF2
$only_es
EOF2
        fi

        common=$(comm -12 <(printf '%s\n' "$en_files") <(printf '%s\n' "$es_files"))
        if [ -n "$common" ]; then
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                case "$rel" in *.html) ;; *) continue ;; esac
                local ef sf ec_pre sc_pre ec_h2 sc_h2
                ef="$root/$rel"; sf="$root/es/$rel"
                ec_pre=$(grep -c '<pre' "$ef" 2>/dev/null || true)
                sc_pre=$(grep -c '<pre' "$sf" 2>/dev/null || true)
                ec_h2=$(grep -c '<h2' "$ef" 2>/dev/null || true)
                sc_h2=$(grep -c '<h2' "$sf" 2>/dev/null || true)
                if [ "${ec_pre:-0}" != "${sc_pre:-0}" ] || [ "${ec_h2:-0}" != "${sc_h2:-0}" ]; then
                    print_bad "[G] $rel: <pre> en=${ec_pre:-0}/es=${sc_pre:-0}, <h2> en=${ec_h2:-0}/es=${sc_h2:-0}"
                    fails=$((fails + 1))
                fi
            done <<EOF2
$common
EOF2
        fi
    else
        print_warn "[G] $root/es no existe — sin paridad EN/ES que comparar todavía"
        warns=$((warns + 1))
    fi

    # Claves de i18n
    local en_toml="$site_dir/content/i18n/en.toml" es_toml="$site_dir/content/i18n/es.toml"
    if [ -f "$en_toml" ] && [ -f "$es_toml" ]; then
        local en_keys es_keys
        # [a-z_0-9], no [a-z_]: una clave con un dígito (p.ej. `nav_v2 = …`)
        # no coincidía en NINGUNO de los dos lados, así que la comparación
        # pasaba en verde sin haber comparado esa clave.
        en_keys=$(grep -o '^[a-z_0-9]* =' "$en_toml" | sort)
        es_keys=$(grep -o '^[a-z_0-9]* =' "$es_toml" | sort)
        if [ "$en_keys" != "$es_keys" ]; then
            print_bad "[G] content/i18n/en.toml y es.toml no tienen las mismas claves:"
            diff <(printf '%s\n' "$en_keys") <(printf '%s\n' "$es_keys") | sed 's/^/      /'
            fails=$((fails + 1))
        fi
    fi

    # content/**/*.en.html <-> *.es.html
    local content_dir="$site_dir/content"
    if [ -d "$content_dir" ]; then
        while IFS= read -r enf; do
            [ -z "$enf" ] && continue
            local esf="${enf%.en.html}.es.html"
            if [ ! -f "$esf" ]; then
                print_bad "[G] content: falta el par ES de $enf"
                fails=$((fails + 1))
            fi
        done < <(find "$content_dir" -type f -name '*.en.html' 2>/dev/null | sort)

        # Prosa pendiente. `scripts/sync-recipes.sh` siembra un STUB de sidecar
        # para cada receta nueva del monorepo que no tiene prosa heredada, y ese
        # stub queda lleno de TODO A PROPÓSITO: es preferible que la guardia se
        # ponga en rojo a publicar una receta muda o, peor, con prosa inventada.
        # El rojo se apaga escribiendo la prosa, no borrando la palabra.
        while IFS= read -r todof; do
            [ -z "$todof" ] && continue
            print_bad "[G] content: prosa pendiente (TODO) en ${todof#$site_dir/}"
            fails=$((fails + 1))
        done < <(grep -rl 'TODO' "$content_dir" --include='*.html' 2>/dev/null | sort)
    fi

    if [ "$fails" -eq 0 ]; then
        print_ok "[G] 0 asimetrías estructurales ($warns aviso(s) de rollout incremental)"
    else
        print_bad "[G] $fails asimetría(s) estructural(es) ($warns aviso(s) aparte)"
    fi
    CHECK_LAST_FAILS=$fails
    CHECK_LAST_WARNS=$warns
}

# ── H. Español neutro (excepto learn/) ───────────────────────────────────
# site_dir se deriva de $root (como check_g, check_j y check_l), no de la
# global SITE_DIR: las cuatro funciones que miran content/ tienen ahora la
# misma forma, y ninguna evalúa un sitio distinto del que le pasaron.
check_h() {
    local root="$1"
    local site_dir; site_dir="$(dirname "$root")"
    local files n=0
    # LEGADO: mismo criterio que A-D — es/learn/ es contenido preexistente
    # que gen-site.sh copia tal cual de static/ y que nadie reescribe; el
    # voseo que ya tenía no es una regresión de este rediseño. Reutiliza
    # legacy_prune_args (la cláusula de learn/ sin es/ es inerte acá: el
    # find ya está anclado bajo "$root/es").
    legacy_prune_args "$root"
    files=$(find "$root/es" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' \) \
        "${LEGACY_PRUNE[@]}" 2>/dev/null | sort)
    if [ -d "$site_dir/content" ]; then
        local content_es
        content_es=$(find "$site_dir/content" -type f -name '*.es.*' 2>/dev/null | sort)
        files="$files
$content_es"
    fi
    scan_denylist "H" "$VOSEO_RE" "$files"
}

# ── I. Salida al día ──────────────────────────────────────────────────────
check_i() {
    local root="$1"
    local fails=0

    if ! command -v nyx >/dev/null 2>&1; then
        # ✗, no ⚠ (fix round 2): esta guardia corre en máquinas con la
        # toolchain instalada — que falte `nyx` no es un estado válido para
        # dar por buena la frescura, es no poder verificarla.
        print_bad "[I] nyx no está en PATH — no se puede verificar la frescura de $root"
        CHECK_LAST_FAILS=1
        return
    fi
    if [ ! -f "$SITE_DIR/gen.nx" ]; then
        print_warn "[I] $SITE_DIR/gen.nx no existe — se salta (root sin generador al lado)"
        CHECK_LAST_FAILS=0
        return
    fi

    local out_base log
    out_base="$(basename "$root")"
    log="$(mktemp "${TMPDIR:-/tmp}/check-content-gencheck.XXXXXX")"
    if (cd "$SITE_DIR" && nyx gen.nx --out "$out_base" --check) >"$log" 2>&1; then
        print_ok "[I] gen.nx --check: $root coincide con la generación actual"
    else
        print_bad "[I] gen.nx --check reporta $root desactualizado:"
        sed 's/^/      /' "$log"
        fails=$((fails + 1))
    fi
    rm -f "$log"

    # Huérfanos: --check no ve archivos DE MÁS en <out>. Comparamos el
    # LISTADO completo contra una generación fresca en un temporal aparte.
    local fresh fresh_files root_files only_root only_fresh
    fresh="$(mktemp -d "${TMPDIR:-/tmp}/check-content-fresh.XXXXXX")"
    (cd "$SITE_DIR" && nyx gen.nx --out "$fresh") >/dev/null 2>&1
    fresh_files=$(find "$fresh" -type f 2>/dev/null | sed "s#^$fresh/##" | sort)
    # LEGADO: la misma lista que A-D/H (legacy_prune_args) — gen.nx no
    # produce learn/, es/learn/ ni shared/nyx-design-system.css: los copia
    # gen-site.sh tal cual, así que no son huérfanos reales. by-example/ SÍ
    # se compara desde la fase 2 (gen.nx lo genera).
    # install.sh se suma acá aparte (no en legacy_prune_args: A-D lo
    # descartan solo por extensión, .sh no es .html/.css/.js — pero el
    # listado de I no filtra por extensión) por la misma razón de fondo:
    # es el shim que copia gen-site.sh, gen.nx tampoco lo genera. logo.png
    # va por la misma puerta: la ruta /logo.png sigue registrada en
    # src/main.nx y gen-site.sh copia el archivo con `cp` (binario), gen.nx
    # no lo produce.
    legacy_prune_args "$root"
    root_files=$(find "$root" -type f "${LEGACY_PRUNE[@]}" \
        -not -path "$root/install.sh" -not -path "$root/logo.png" 2>/dev/null \
        | sed "s#^$root/##" | sort)
    rm -rf "$fresh"

    only_root=$(comm -13 <(printf '%s\n' "$fresh_files") <(printf '%s\n' "$root_files"))
    only_fresh=$(comm -23 <(printf '%s\n' "$fresh_files") <(printf '%s\n' "$root_files"))

    if [ -z "$only_root" ] && [ -z "$only_fresh" ]; then
        print_ok "[I] listado de archivos: $root == generación fresca"
    else
        if [ -n "$only_root" ]; then
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                print_bad "[I] huérfano en $root (gen.nx ya no lo produce): $rel"
                fails=$((fails + 1))
            done <<EOF
$only_root
EOF
        fi
        if [ -n "$only_fresh" ]; then
            while IFS= read -r rel; do
                [ -z "$rel" ] && continue
                print_bad "[I] gen.nx produce $rel y no está en $root"
                fails=$((fails + 1))
            done <<EOF
$only_fresh
EOF
        fi
    fi

    CHECK_LAST_FAILS=$fails
}

# Literales X.Y.Z de un texto, SIN los que son parte de un número punteado más
# largo: «127.0.0.1» contiene «127.0.0», que no es una versión sino una IPv4, y
# el recetario publica varias (45-dns-resolve, 47-tcp-server). Se rechaza un
# candidato si lo precede un dígito o un punto, o si lo sigue un dígito, o si lo
# sigue un punto y otro dígito. awk con match() porque `grep -oE` no tiene
# lookaround y el contexto de un byte es justo lo que hace falta mirar.
version_literals() {
    printf '%s\n' "$1" | awk '
    {
        base = 0
        rest = $0
        while (match(rest, /[0-9]+\.[0-9]+\.[0-9]+/)) {
            s = RSTART; l = RLENGTH
            lit = substr(rest, s, l)
            before = (base + s > 1) ? substr($0, base + s - 1, 1) : ""
            aft1 = substr($0, base + s + l, 1)
            aft2 = substr($0, base + s + l + 1, 1)
            if (before !~ /[0-9.]/ && aft1 !~ /[0-9]/ && !(aft1 == "." && aft2 ~ /[0-9]/))
                print lit
            base = base + s + l - 1
            rest = substr($0, base + 1)
        }
    }'
}

# ── J. Versión publicada == versión del toolchain ────────────────────────
# site_dir se deriva de $root (no se usa la global SITE_DIR) para que el
# autotest pueda plantar un sitio-fixture completo — content/ + árbol
# publicado — y ver el ✗ de verdad.
#
# Exenciones para un literal X.Y.Z que NO es la versión del toolchain:
#   <!-- not-a-version -->          en la misma línea
#   <!-- not-a-version: 0.1.0 -->   ese literal, en todo el archivo
# (ver la nota de la cabecera: dentro de un <pre> un comentario HTML se ve).
check_j() {
    local root="$1"
    local site_dir; site_dir="$(dirname "$root")"
    local fails=0

    if ! command -v nyx >/dev/null 2>&1; then
        print_bad "[J] nyx no está en PATH — no se puede comparar la versión publicada con la del toolchain"
        CHECK_LAST_FAILS=1
        return
    fi

    local nyx_ver
    nyx_ver="$(nyx --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$nyx_ver" ]; then
        print_bad "[J] « nyx --version » no devolvió una versión X.Y.Z"
        CHECK_LAST_FAILS=1
        return
    fi

    local toml="$site_dir/content/site.toml" toml_ver
    if [ -f "$toml" ]; then
        toml_ver="$(grep -E '^version[[:space:]]*=' "$toml" | head -1 \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ "$toml_ver" = "$nyx_ver" ]; then
            print_ok "[J] content/site.toml: version = $toml_ver == nyx --version"
        else
            print_bad "[J] content/site.toml: version = ${toml_ver:-<ninguna>} != $nyx_ver (nyx --version)"
            fails=$((fails + 1))
        fi
    else
        print_warn "[J] $toml no existe — sin sello de versión que comparar"
    fi

    local dirs d f exempt line lineno text lit checked=0
    dirs="$site_dir/content/docs
$site_dir/content/landing
$site_dir/content/by-example"
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            # El literal se toma del propio marcador; después del número
            # puede seguir texto explicativo, siempre DENTRO del comentario.
            exempt="$(grep -oE '<!--[[:space:]]*not-a-version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null \
                | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                lineno="${line%%:*}"
                text="${line#*:}"
                # exención de línea
                case "$text" in *not-a-version*) continue ;; esac
                while IFS= read -r lit; do
                    [ -z "$lit" ] && continue
                    checked=$((checked + 1))
                    if [ "$lit" = "$nyx_ver" ]; then continue; fi
                    case "
$exempt
" in *"
$lit
"*) continue ;; esac
                    print_bad "[J] $f:$lineno: literal « $lit » != $nyx_ver (nyx --version) — si no es una versión del toolchain, márcalo con <!-- not-a-version: $lit -->"
                    fails=$((fails + 1))
                done <<EOF
$(version_literals "$text")
EOF
            done < <(grep -nE '[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null)
        done < <(find "$d" -type f -name '*.html' 2>/dev/null | sort)
    done <<EOF
$dirs
EOF

    if [ "$fails" -eq 0 ]; then
        print_ok "[J] $checked literal(es) X.Y.Z en content/ coinciden con nyx $nyx_ver (o están exentos)"
    else
        print_bad "[J] $fails desajuste(s) de versión"
    fi
    CHECK_LAST_FAILS=$fails
}

# ── K. HTML publicado sin agujeros ───────────────────────────────────────
# Una clave i18n ausente interpola "" en silencio (src/gen/render.nx:18) y
# title_key/desc_key salen de get_or(..., ""), así que un `stem` mal escrito
# publica un <title>/<h1> vacío en los DOS idiomas y G sigue en verde
# (compara EN contra ES, no contra un valor esperado). Esto lo mira contra
# un valor esperado: que no esté vacío.
check_k() {
    local root="$1"
    local files n=0 f label pat hit
    files=$(find_nolegacy "$root" -name '*.html')
    [ -z "$files" ] && { print_ok "[K] 0 archivos que revisar"; CHECK_LAST_FAILS=0; return; }

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pat in \
            'titulo vacio:<title>[[:space:]]*</title>' \
            'meta description vacia:name="description"[^>]*content=""' \
            'h1 vacio:<h1[^>]*>[[:space:]]*</h1>' \
            'h2 vacio:<h2[^>]*>[[:space:]]*</h2>'
        do
            label="${pat%%:*}"
            while IFS= read -r hit; do
                [ -z "$hit" ] && continue
                print_bad "[K] $label — $f:$hit"
                n=$((n + 1))
            done < <(grep -nE -- "${pat#*:}" "$f" 2>/dev/null)
        done
        # `{{` residual: FUERA de <pre> y de <code>. La convención (fase 2):
        # dentro de un bloque de código o de un <code> inline, `{{` es el
        # tema del que habla la página — la receta 102 enseña std/template y
        # muestra `{{clave}}`, `{{{crudo}}}` y `{{#each}}` tanto en su código
        # como en su explicación. Fuera de ahí sigue siendo lo que este check
        # persigue: una interpolación que el generador no resolvió. strip_pre
        # conserva una línea de salida por línea de entrada, así que los
        # números de línea que reporta grep -n siguen siendo los del archivo.
        while IFS= read -r hit; do
            [ -z "$hit" ] && continue
            print_bad "[K] interpolacion residual — $f:$hit"
            n=$((n + 1))
        done < <(strip_pre "$f" | strip_code | grep -nE -- '{{' 2>/dev/null)
    done <<EOF
$files
EOF

    if [ "$n" -eq 0 ]; then
        print_ok "[K] 0 títulos/encabezados vacíos, 0 meta description vacía, 0 {{ residual"
    else
        print_bad "[K] $n agujero(s) en el HTML publicado"
    fi
    CHECK_LAST_FAILS=$n
}

# ── L. El recetario publicado sale del monorepo, sin drift ───────────────
# El código de cada receta tiene UNA fuente de verdad: examples/by-example/ del
# monorepo del lenguaje. `scripts/sync-recipes.sh --check` compara copia por
# copia (y la versión de content/site.toml contra VERSION), sin escribir nada.
# Sin esto, el sitio podía publicar código que el monorepo ya no tiene — que es
# exactamente la clase de mentira que este rediseño existe para reparar.
#
# Este check mira content/, no el árbol publicado: es la única guardia que sale
# del repo (necesita el monorepo). Si no lo encuentra, avisa con ⚠ y no falla —
# un clon sin el monorepo al lado no puede verificar el drift, pero tampoco es
# un hallazgo de contenido.
check_l() {
    local root="$1"
    local site_dir; site_dir="$(dirname "$root")"

    CHECK_LAST_LOG=""
    if [ ! -f "$site_dir/content/by-example/recipes.toml" ]; then
        print_warn "[L] $site_dir/content/by-example/recipes.toml no existe — se salta (root sin recetario al lado)"
        CHECK_LAST_FAILS=0
        return
    fi
    local mono="${NYX_MONOREPO:-/home/admin/nyx/lang}"
    if [ ! -d "$mono/examples/by-example" ]; then
        print_warn "[L] no está $mono/examples/by-example — no se puede verificar el drift del recetario (¿NYX_MONOREPO?)"
        CHECK_LAST_FAILS=0
        return
    fi

    # NYX_SITE_DIR: sin esto sync-recipes.sh evaluaba SIEMPRE el
    # nyxlang.com/content del repo, ignorando el $root recibido — así el
    # autotest no podía plantarle un drift en su propio sitio-fixture y L era
    # el único check que no se medía a sí mismo.
    local log w
    log="$(mktemp "${TMPDIR:-/tmp}/check-content-recipes.XXXXXX")"
    if NYX_SITE_DIR="$site_dir" NYX_MONOREPO="$mono" \
       bash "$REPO_ROOT/scripts/sync-recipes.sh" --check >"$log" 2>&1; then
        # Los ⚠ del script (sidecars cuyo slug no está en el catálogo) son
        # avisos, no fallos: se imprimen igual o nadie los ve nunca.
        while IFS= read -r w; do
            [ -z "$w" ] && continue
            print_warn "[L] $w"
        done < <(grep '⚠' "$log" 2>/dev/null | sed 's/^ *⚠ *//')
        print_ok "[L] $(tail -1 "$log")"
        CHECK_LAST_FAILS=0
    else
        print_bad "[L] el recetario del sitio no coincide con el monorepo:"
        sed 's/^/      /' "$log"
        CHECK_LAST_FAILS=1
    fi
    CHECK_LAST_LOG="$(cat "$log")"
    rm -f "$log"

    # Mirror público (AVISO, nunca ✗): los enlaces «Source →» de las 69 páginas
    # apuntan al mirror, no al monorepo privado, y el mirror se sincroniza en el
    # paso 8 del runbook — DESPUÉS del swap. Que difiera antes del cutover es lo
    # esperado; que nadie lo mire, no.
    local mlog
    mlog="$(mktemp "${TMPDIR:-/tmp}/check-content-mirror.XXXXXX")"
    NYX_SITE_DIR="$site_dir" NYX_MONOREPO="$mono" \
        bash "$REPO_ROOT/scripts/sync-recipes.sh" --check-mirror >"$mlog" 2>&1
    if grep -q 'al día con el mirror' "$mlog"; then
        print_ok "[L] $(tail -1 "$mlog")"
    else
        while IFS= read -r w; do
            [ -z "$w" ] && continue
            print_warn "[L] $w"
        done < <(sed 's/^ *⚠ *//' "$mlog")
    fi
    rm -f "$mlog"
}

# ── Autotest (control positivo) — corre SIEMPRE primero ─────────────────
run_autotest() {
    banner "autotest (control positivo)"
    local tmp broken=0 site aroot
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-content-autotest.XXXXXX")"
    # Sitio-fixture COMPLETO (content/ + árbol publicado), no un solo HTML
    # suelto: J compara content/site.toml y los literales de content/docs
    # contra `nyx --version`, y G compara el listado EN contra el ES bajo el
    # root. Los dos necesitan la forma de un sitio para poder fallar.
    site="$tmp/site"
    aroot="$site/static-next"
    mkdir -p "$aroot/es" "$site/content/docs"

    # A (nyx-kv), B (req/s + «más rápido que»), C (macOS), E (#products),
    # F (enlace roto), K (<title> vacío + {{ residual}).
    cat > "$aroot/index.html" <<'HTML'
<!doctype html>
<html>
<head><title></title></head>
<body>
<p>nyx-kv procesa 9,971 req/s, mucho más rápido que la competencia en macOS.</p>
<p>El formato binario es ~30% smaller than JSON y un 12% menos pesado que YAML.</p>
<a href="/no-existe.html">enlace roto</a>
<a href="/es/#products">ancla muerta</a>
<p>{{clave_que_no_existe}}</p>
<pre>{{ok_en_pre}}</pre>
<p>La receta 102 escribe <code>{{ok_en_code}}</code> como tema, no como interpolación.</p>
</body>
</html>
HTML
    cp "$aroot/index.html" "$aroot/es/index.html"
    # G: una página EN sin gemela ES → ⚠ (por diseño no es ✗: el rollout
    # incremental no se bloquea, se hace visible).
    printf '<p>pagina sin par ES</p>\n' > "$aroot/solo-en.html"

    # J: site.toml con una versión que no es la del toolchain, un literal
    # X.Y.Z equivocado en content/docs, y un literal EXENTO que no debe
    # contar (control negativo adentro del positivo: si la exención se
    # rompiera y contara 3, el autotest también lo ve).
    printf 'version = "0.0.1"\n' > "$site/content/site.toml"
    cat > "$site/content/docs/fixture.en.html" <<'HTML'
<!-- not-a-version: 0.1.0 -->
<p>La toolchain dice 9.9.9 y el proyecto de ejemplo va en 0.1.0.</p>
HTML
    # Par ES del fragmento, sin literales de versión: G exige que cada
    # content/**/*.en.html tenga su .es.html, y el fixture tiene que ser un
    # sitio bien formado en todo lo que NO es el error plantado. Sin literales
    # para que J siga contando exactamente 2.
    printf '<p>Par ES del fragmento del autotest.</p>\n' > "$site/content/docs/fixture.es.html"

    check_a "$aroot"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: A no detectó el control positivo"; broken=1; }
    # Exactamente 4, no «≥1»: son DOS líneas plantadas (la de req/s y la del
    # porcentaje comparativo, que es lo único que ejercita el patrón nuevo de
    # la fase 2) por DOS copias del fixture (index.html y su gemela es/). Con
    # «≥1» la línea de req/s sola alcanzaba para dar el autotest por bueno y
    # el patrón del porcentaje podía quedarse ciego sin que nadie lo viera.
    check_b "$aroot"; [ "$CHECK_LAST_FAILS" -eq 4 ] || { print_bad "AUTOTEST ROTO: B vio $CHECK_LAST_FAILS hallazgo(s), esperaba 4 (req/s + porcentaje comparativo, en index.html y en es/index.html)"; broken=1; }
    check_c "$aroot"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: C no detectó el control positivo"; broken=1; }
    check_e "$aroot"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: E no detectó el control positivo"; broken=1; }
    check_f "$aroot"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: F no detectó el control positivo"; broken=1; }
    check_g "$aroot"; [ "$CHECK_LAST_WARNS" -ge 1 ] || { print_bad "AUTOTEST ROTO: G no vio la página EN sin gemela ES"; broken=1; }
    # Exactamente 4: <title> vacío + el {{ de un <p>, por las dos copias del
    # fixture. Ni 2 (el sub-check de `{{` fuera de <pre>/<code> —lo único que
    # la fase 2 le cambió a K— se quedó ciego) ni 6 u 8 (strip_pre/strip_code
    # dejaron de proteger el `{{ok_en_pre}}` y el `{{ok_en_code}}`, que son
    # control NEGATIVO: la receta 102 publica esa sintaxis como tema de la
    # página). Con «≥1» el <title> vacío solo daba el autotest por bueno.
    check_k "$aroot"; [ "$CHECK_LAST_FAILS" -eq 4 ] || { print_bad "AUTOTEST ROTO: K vio $CHECK_LAST_FAILS hallazgo(s), esperaba 4 (<title> vacío + {{ en un <p>, en index.html y en es/index.html; los {{ de <pre> y <code> no cuentan)"; broken=1; }

    check_j "$aroot"
    if command -v nyx >/dev/null 2>&1; then
        # Exactamente 2: el site.toml y el 9.9.9. Ni 1 (se le escapó uno) ni
        # 3 (la exención <!-- not-a-version: 0.1.0 --> dejó de funcionar).
        [ "$CHECK_LAST_FAILS" -eq 2 ] || { print_bad "AUTOTEST ROTO: J vio $CHECK_LAST_FAILS hallazgo(s), esperaba 2 (site.toml + 9.9.9, con 0.1.0 exento)"; broken=1; }
    else
        [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: J no detectó el control positivo"; broken=1; }
    fi

    # L: control positivo propio (era el único check que no se medía a sí
    # mismo). Se planta un sitio-fixture con su catálogo y su copia de receta,
    # y un "monorepo" de mentira cuyo .nx del mismo slug tiene un byte
    # distinto: L tiene que ver EXACTAMENTE 1 hallazgo (el drift). La versión
    # del VERSION falso se hace coincidir con el site.toml del fixture para
    # que el desajuste de versión —que L también reporta— no enmascare al
    # drift ni sume un segundo hallazgo.
    local fmono="$tmp/mono"
    mkdir -p "$fmono/examples/by-example" "$site/content/by-example/src"
    printf '0.0.1\n' > "$fmono/VERSION"
    cat > "$site/content/by-example/recipes.toml" <<'TOML'
order = "01-fixture"

[r01]
slug = "01-fixture"
num = "01"
category = "fundamentals"
excluded = "0"
sidecar = "1"
TOML
    printf 'fn main() -> int { return 0 }\n' > "$site/content/by-example/src/01-fixture.nx"
    printf 'fn main() -> int { return 1 }\n' > "$fmono/examples/by-example/01-fixture.nx"

    # Las asignaciones delante de la llamada a una FUNCIÓN persisten en bash
    # después de que la función vuelve, así que no se usa esa forma: se
    # exporta, se llama y se restaura el entorno del que corre el script.
    local prev_mono="${NYX_MONOREPO:-}" prev_mirror="${NYX_MIRROR:-}"
    export NYX_MONOREPO="$fmono"
    export NYX_MIRROR="$tmp/sin-mirror-a-proposito"
    check_l "$aroot"
    [ "$CHECK_LAST_FAILS" -eq 1 ] || { print_bad "AUTOTEST ROTO: L vio $CHECK_LAST_FAILS hallazgo(s), esperaba 1 (el .nx del fixture difiere del monorepo falso)"; broken=1; }
    # Y que el hallazgo sea EL del fixture: si L ignorara el $root recibido y
    # evaluara el content/ real contra el monorepo falso, también saldría 1.
    case "$CHECK_LAST_LOG" in
        *01-fixture*) ;;
        *) print_bad "AUTOTEST ROTO: L no nombró la receta del sitio-fixture — evaluó otro content/ (¿se perdió NYX_SITE_DIR?)"; broken=1 ;;
    esac
    if [ -n "$prev_mono" ]; then export NYX_MONOREPO="$prev_mono"; else unset NYX_MONOREPO; fi
    if [ -n "$prev_mirror" ]; then export NYX_MIRROR="$prev_mirror"; else unset NYX_MIRROR; fi

    rm -rf "$tmp"

    if [ "$broken" -eq 1 ]; then
        printf '\nEl script de guardias está ROTO: no ve sus propios controles positivos.\n'
        printf 'Abortando antes de evaluar el árbol real.\n'
        exit 2
    fi
    print_ok "autotest: A, B, C, E, F, G, J, K y L detectan el control positivo — el instrumento sirve"
}

# ── Piso mínimo (fix round 2) ─────────────────────────────────────────────
# Sin esto: un ROOT vacío, a medio generar, o con un typo de path, hacía que
# A-D/F/H dieran "✓ 0 coincidencias" (nada que escanear no es lo mismo que
# nada sospechoso) e I se salteara con ⚠ si además faltaba `nyx` — la
# guardia daba rc=0 sobre la nada. Corre SIEMPRE, sin depender de `nyx` ni
# de que exista `gen.nx` al lado (a diferencia del check I): dos archivos
# concretos + un volumen mínimo de HTML fuera del legado. Mismo trato que
# el autotest roto — sin piso, no tiene sentido evaluar nada más.
MIN_HTML_FILES=20

check_floor() {
    local root="$1"
    local broken=0 n

    if [ ! -f "$root/index.html" ]; then
        print_bad "GUARDIA SIN MATERIAL: falta $root/index.html"
        broken=1
    fi
    if [ ! -f "$root/es/index.html" ]; then
        print_bad "GUARDIA SIN MATERIAL: falta $root/es/index.html"
        broken=1
    fi

    # "El legado" acá es learn/+es/learn/, que desde la fase 2 coincide con
    # `find_nolegacy` salvo por shared/nyx-design-system.css (un .css, que
    # este conteo de .html no mira igual). Se mantiene explícito y no se
    # deriva de legacy_prune_args a propósito: el piso mide "¿hay un sitio
    # acá?", y esa pregunta no debe cambiar de significado cada vez que un
    # directorio entra o sale de la lista de exenciones.
    n=$(find "$root" -type f -name '*.html' \
        -not -path "$root/learn/*" -not -path "$root/es/learn/*" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -lt "$MIN_HTML_FILES" ]; then
        print_bad "GUARDIA SIN MATERIAL: $n archivo(s) .html fuera de learn/ en $root (mínimo $MIN_HTML_FILES)"
        broken=1
    fi

    if [ "$broken" -eq 1 ]; then
        printf '\nEl árbol no tiene material suficiente para que esta guardia signifique algo.\n'
        printf 'Abortando antes de evaluar los checks.\n'
        exit 2
    fi
    print_ok "piso mínimo: index.html + es/index.html + $n archivo(s) .html fuera de learn/"
}

# ── main ──────────────────────────────────────────────────────────────────
run_autotest
check_floor "$ROOT"

TOTAL_FAIL=0
for c in a b c d e f g h i j k l; do
    banner "check $c ($ROOT)"
    "check_$c" "$ROOT"
    TOTAL_FAIL=$((TOTAL_FAIL + CHECK_LAST_FAILS))
done

banner "resumen"
if [ "$TOTAL_FAIL" -eq 0 ]; then
    print_ok "check-content: 0 hallazgos en $ROOT"
    exit 0
else
    print_bad "check-content: $TOTAL_FAIL hallazgo(s) en $ROOT"
    exit 1
fi
