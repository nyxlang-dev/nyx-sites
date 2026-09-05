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
#      existe el .es.html.
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
#   J. Autotest (control positivo): corre PRIMERO, siempre. Crea un ROOT
#      temporal con un HTML que dispara A, B, C, E y F a propósito; si
#      alguno de los cinco no lo detecta, el script se declara ROTO y sale 2
#      antes de tocar el árbol real — un guardia que no ve sus propios
#      controles positivos no prueba nada estando en verde.
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
# LEGADO (TRANSITORIO — fix round 1, ruling del coordinador): en la fase 1
# del rediseño, static-next/ tiene que seguir sirviendo el by-example VIEJO
# — los AGENTS.md que siembra `nyx init` enlazan a mano
# https://nyxlang.com/by-example/, así que la T7 va a copiar tal cual a
# static-next/ los directorios learn/, es/learn/, by-example/, es/by-example/
# y el archivo shared/nyx-design-system.css (las páginas legado lo
# necesitan). Mientras ese contenido no se vuelva a generar (fase 2:
# by-example regenerado por gen.nx), A/B/C/D no lo escanean — sería puro
# ruido sobre contenido que nadie tocó. E (anclas muertas) y F (enlaces
# internos) SÍ lo escanean completo: son regresiones reales incluso en
# contenido legado, y la T7 es quien parchea sus anclas. G lo excluye igual
# que a `shared/`: no es contenido que declare paridad EN/ES bajo este
# esquema. Cuando by-example/ se regenere, `by-example/` y `es/by-example/`
# salen de esta lista (learn/es/learn y shared/nyx-design-system.css se
# quedan: son legado permanente, no de la fase 1 nada más).
#
# LEGADO en H e I (T7, gen-site.sh): la misma lista de arriba (learn/,
# es/learn/, by-example/, es/by-example/, shared/nyx-design-system.css —
# via legacy_prune_args, sin duplicar rutas) pasa a excluirse TAMBIÉN en
# H (español neutro: ese contenido es preexistente, se regenera recién en
# la fase 2) y en I (salida al día: gen.nx no lo produce, lo copia
# gen-site.sh — no son huérfanos reales). I suma además install.sh solo,
# aparte de legacy_prune_args: A-D ya lo descartan por extensión (.sh no
# es .html/.css/.js) así que no hacía falta en esa lista, pero el listado
# de I no filtra por extensión y gen.nx tampoco genera ese shim.
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
METRICS_RE='req/s|ops/s|[0-9][0-9.,]*\s*(ms|µs|x faster|× faster|veces más rápido)|benchmark|faster than|más rápido que|[0-9]+ (recipes|recetas|tests|seconds|segundos)'
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

# Lista archivos bajo $1=root con los predicados -name que sigan ($2, $3…),
# excluyendo el LEGADO (ver comentario arriba de `set -u`). Usada por A, B,
# C y D — no por E/F (que sí escanean el legado) ni por G (que tiene su
# propia lista de exclusiones, learn/shared/install.sh/by-example, porque
# compara EN contra ES en vez de listar un solo lado).
# Predicados -not -path del LEGADO (learn/es/learn/by-example/es/by-example
# + shared/nyx-design-system.css) para un $root dado. Una sola función que
# find_nolegacy (A-D), check_h y check_i (T7) reutilizan tal cual — no
# duplicar esta lista de rutas en más de un lugar.
legacy_prune_args() {
    local root="$1"
    LEGACY_PRUNE=(
        -not -path "$root/learn/*"
        -not -path "$root/es/learn/*"
        -not -path "$root/by-example/*"
        -not -path "$root/es/by-example/*"
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
check_g() {
    local root="$1"
    local fails=0 warns=0

    if [ -d "$root/es" ]; then
        local en_files es_files only_en only_es common
        en_files=$(find "$root" -type f \
            -not -path "$root/es/*" -not -path "$root/learn/*" \
            -not -path "$root/by-example/*" \
            -not -path "$root/shared/*" -not -name "install.sh" 2>/dev/null \
            | sed "s#^$root/##" | sort)
        es_files=$(find "$root/es" -type f \
            -not -path "$root/es/learn/*" -not -path "$root/es/by-example/*" 2>/dev/null \
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
    local en_toml="$SITE_DIR/content/i18n/en.toml" es_toml="$SITE_DIR/content/i18n/es.toml"
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
    local content_dir="$SITE_DIR/content"
    if [ -d "$content_dir" ]; then
        while IFS= read -r enf; do
            [ -z "$enf" ] && continue
            local esf="${enf%.en.html}.es.html"
            if [ ! -f "$esf" ]; then
                print_bad "[G] content: falta el par ES de $enf"
                fails=$((fails + 1))
            fi
        done < <(find "$content_dir" -type f -name '*.en.html' 2>/dev/null | sort)
    fi

    if [ "$fails" -eq 0 ]; then
        print_ok "[G] 0 asimetrías estructurales ($warns aviso(s) de rollout incremental)"
    else
        print_bad "[G] $fails asimetría(s) estructural(es) ($warns aviso(s) aparte)"
    fi
    CHECK_LAST_FAILS=$fails
}

# ── H. Español neutro (excepto learn/) ───────────────────────────────────
check_h() {
    local root="$1"
    local files n=0
    # LEGADO (T7): mismo criterio que A-D — es/learn y es/by-example son
    # contenido preexistente que gen-site.sh copia tal cual de static/ y
    # se regenera recién en la fase 2; hasta entonces el voseo que ya
    # tenía no es una regresión de este rediseño. Reutiliza
    # legacy_prune_args (las cláusulas de learn/ y by-example/ sin es/ son
    # inertes acá, el find ya está anclado bajo "$root/es").
    legacy_prune_args "$root"
    files=$(find "$root/es" -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' \) \
        "${LEGACY_PRUNE[@]}" 2>/dev/null | sort)
    if [ -d "$SITE_DIR/content" ]; then
        local content_es
        content_es=$(find "$SITE_DIR/content" -type f -name '*.es.*' 2>/dev/null | sort)
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
    # LEGADO (T7): la misma lista que A-D/H (legacy_prune_args) — gen.nx no
    # produce learn/es/learn/by-example/es/by-example/shared/nyx-design-system.css,
    # los copia gen-site.sh tal cual, así que no son huérfanos reales.
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

# ── J. Autotest (control positivo) — corre SIEMPRE primero ──────────────
run_autotest() {
    banner "J — autotest (control positivo)"
    local tmp broken=0
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-content-autotest.XXXXXX")"
    cat > "$tmp/index.html" <<'HTML'
<!doctype html>
<html>
<head><title>fixture</title></head>
<body>
<p>nyx-kv procesa 9,971 req/s, mucho más rápido que la competencia en macOS.</p>
<a href="/no-existe.html">enlace roto</a>
<a href="/es/#products">ancla muerta</a>
</body>
</html>
HTML

    check_a "$tmp"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: A no detectó el control positivo"; broken=1; }
    check_b "$tmp"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: B no detectó el control positivo"; broken=1; }
    check_c "$tmp"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: C no detectó el control positivo"; broken=1; }
    check_e "$tmp"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: E no detectó el control positivo"; broken=1; }
    check_f "$tmp"; [ "$CHECK_LAST_FAILS" -ge 1 ] || { print_bad "AUTOTEST ROTO: F no detectó el control positivo"; broken=1; }

    rm -rf "$tmp"

    if [ "$broken" -eq 1 ]; then
        printf '\nEl script de guardias está ROTO: no ve sus propios controles positivos.\n'
        printf 'Abortando antes de evaluar el árbol real.\n'
        exit 2
    fi
    print_ok "autotest: A, B, C, E y F detectan el control positivo — el instrumento sirve"
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

    # OJO — "el legado" acá es MÁS ANGOSTO que `find_nolegacy` (A-D/G/H/I):
    # solo learn/+es/learn/ (el legado PERMANENTE, nunca enlazado — la
    # definición original de la T6, antes de que la T7 sumara by-example/
    # como excepción TRANSITORIA de fase 1). Con la lista completa de
    # find_nolegacy, tanto static-next (16 páginas propias: landing+docs)
    # como static (2: solo index.html/es/index.html, todo lo demás es
    # by-example/learn) quedan por debajo de cualquier piso razonable — el
    # piso dejaría de medir "¿hay un sitio acá?" y pasaría a medir "¿ya se
    # regeneró by-example?", que es el trabajo de I, no de esto. by-example
    # es contenido real y enlazado (a diferencia de learn/): cuenta para
    # "hay material", aunque A-D no lo escaneen todavía.
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
for c in a b c d e f g h i; do
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
