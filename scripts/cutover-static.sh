#!/usr/bin/env bash
# cutover-static.sh — intercambia static/ ↔ static-next/ de un sitio en UNA
# syscall (mv --exchange, coreutils ≥ 9.7), sin restart y sin ventana.
#
# Uso: bash scripts/cutover-static.sh <swap|rollback|status> [SITE_DIR]
#   SITE_DIR: default "nyxlang.com", relativo a la raíz del repo; también
#             acepta una ruta absoluta.
# Variables:
#   PORT     (default 3001)                    puerto contra el que se verifica
#   BASE_URL (default http://127.0.0.1:$PORT)  base de las verificaciones curl
#
# Contrato completo: docs/design (T12) — resumen:
#   status   — imprime la GENERACIÓN de static/ y static-next/ (fase 2, fase 1
#              o sitio viejo — ver site_generation) y si el servidor
#              responde. Sale 0.
#   swap     — precondiciones (TODAS o aborta sin tocar nada): mv soporta
#              --exchange; static/ y static-next/ existen y son directorios;
#              static-next/ tiene los archivos mínimos del sitio nuevo y una
#              generación MÁS NUEVA que la publicada en static/; sin
#              cambios sin commitear en esos dos árboles; check-content.sh
#              verde sobre static-next/. Luego `mv --exchange` (una sola
#              llamada) y una verificación curl best-effort (si no hay
#              servidor en $PORT, lo avisa y sigue en verde: no es un fallo
#              de la ensayada, es la ausencia de servidor). Si HAY servidor y
#              alguna verificación falla, sale 2: el intercambio ya se aplicó
#              (es atómico) y el rc distinto de cero es la única señal —
#              `cutover-static.sh swap … && echo ok` no puede dar verde falso.
#   rollback — el mismo `mv --exchange` en sentido inverso (es su propio
#              inverso), con la precondición de que static-next/ tenga una
#              generación ANTERIOR a la de static/ (si no, ya se revirtió o
#              nunca se hizo el swap — no hay nada que revertir). Mismo
#              rc=2 que swap si la verificación posterior falla.
#
# El `mv --exchange` es atómico: o se aplicó entero o no se aplicó. El único
# estado "a mitad de camino" posible es que el intercambio haya salido bien
# pero la VERIFICACIÓN posterior falle (p.ej. el servidor tarda en responder)
# — el trap de abajo avisa de esa distinción para que nadie confunda "la
# verificación falló" con "no se movió nada".

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$0"

ACTION="${1:-}"
SITE_ARG="${2:-nyxlang.com}"
PORT="${PORT:-3001}"
BASE_URL="${BASE_URL:-http://127.0.0.1:$PORT}"

case "$SITE_ARG" in
    /*) SITE_ABS="$SITE_ARG" ;;
    *)  SITE_ABS="$REPO_ROOT/$SITE_ARG" ;;
esac

case "$ACTION" in
    swap|rollback|status) ;;
    *)
        echo "uso: bash $SELF <swap|rollback|status> [SITE_DIR]" >&2
        exit 1
        ;;
esac

abort() {
    echo "ABORTADO: $*" >&2
    echo "(nada se tocó)" >&2
    exit 1
}

# Trap: el mv --exchange en sí es atómico (o pasó entero o no pasó nada);
# lo único que puede fallar "a mitad de camino" es la verificación posterior.
# Si eso pasa, avisar explícitamente para que no se confunda con un
# intercambio parcial (no existe tal cosa con --exchange).
SWAPPED=0
on_exit() {
    local rc=$?
    if [ "$SWAPPED" = "1" ] && [ "$rc" != "0" ]; then
        echo "AVISO: el intercambio (mv --exchange) YA se aplicó antes de esta falla — es atómico, no quedó a mitad de camino. Lo que falló fue la verificación posterior. Revisar con: bash $SELF status $SITE_ARG" >&2
    fi
}
trap on_exit EXIT

# Ruta de un directorio del sitio, relativa a REPO_ROOT (para pathspecs de
# git). Si SITE_ABS cae fuera del repo, se devuelve tal cual (git no la va
# a reconocer y el precondición 4 de swap fallará con un mensaje claro).
site_relpath() {
    case "$1" in
        "$REPO_ROOT"/*) echo "${1#"$REPO_ROOT"/}" ;;
        "$REPO_ROOT")   echo "." ;;
        *)              echo "$1" ;;
    esac
}

# GENERACIÓN del sitio que vive en un directorio. Un número, no un par de
# marcas booleanas, porque el rediseño tiene más de dos estados y las
# precondiciones de swap/rollback son de ORDEN, no de identidad:
#
#   2  fase 2: landing + guía + RECETARIO generados
#   1  fase 1: landing + guía generados, recetario todavía legado (copiado)
#   0  sitio viejo, escrito a mano
#  -1  no se reconoce
#
# La marca de la fase 2 es que el índice del recetario cargue la hoja NUEVA:
# el recetario legado carga shared/nyx-design-system.css, que el sitio
# generado también copia (las páginas de «The Nyx Book» la necesitan), así
# que la presencia del archivo NO distingue nada — hay que mirar quién lo usa.
site_generation() {
    local d="$1"
    if [ -f "$d/shared/spec.css" ] && [ -f "$d/docs/index.html" ]; then
        if [ -f "$d/by-example/index.html" ] && grep -q '/shared/spec.css' "$d/by-example/index.html"; then
            echo 2
        else
            echo 1
        fi
        return
    fi
    if [ -f "$d/shared/nyx-design-system.css" ]; then echo 0; return; fi
    echo -1
}

site_generation_label() {
    case "$1" in
        2) echo "sitio de la FASE 2 (landing + guía + recetario generados)" ;;
        1) echo "sitio de la FASE 1 (landing + guía generados, recetario legado)" ;;
        0) echo "sitio VIEJO (shared/nyx-design-system.css)" ;;
        *) echo "marca desconocida" ;;
    esac
}

mv_exchange_supported() {
    mv --help 2>/dev/null | grep -q -- '--exchange'
}

# Verificación curl best-effort tras un intercambio. $1 = "nuevo" | "anterior"
# según qué generación debería estar viviendo en static/ después de la
# operación. Si el servidor no responde en $PORT (caso normal del ensayo,
# sin servidor levantado), lo dice y omite los curls — eso NO es un fallo.
#
# Cada ruta se resuelve contra el archivo real en disco (static/<relfile>):
# si el archivo no existe en el árbol que quedó activo, se espera 404
# (contrato ya establecido por app_static_cached — ver smoke.sh), no 200 a
# ciegas. Esto es necesario para que la MISMA función sirva para swap
# (static/ pasa a tener el sitio nuevo completo, todo 200) y para rollback
# (static/ vuelve a tener el sitio viejo, que nunca tuvo /docs/ ni
# shared/spec.css — ahí 404 limpio es el resultado correcto, no un error).
verify_site() {
    local expect="$1" site_abs="$2"
    local static="$site_abs/static"

    local root_code
    root_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL/" 2>/dev/null || true)"
    if [ -z "$root_code" ] || [ "$root_code" = "000" ]; then
        echo "AVISO: no hay servidor respondiendo en $BASE_URL — se omiten los curls de verificación (ensayo sin servidor)."
        return 0
    fi

    echo "verificando contra $BASE_URL ..."
    local checks_ok=1
    local entry path relfile want got
    for entry in \
        "/:index.html" \
        "/es/:es/index.html" \
        "/docs/:docs/index.html" \
        "/es/docs/01-install.html:es/docs/01-install.html" \
        "/by-example/:by-example/index.html" \
        "/es/by-example/:es/by-example/index.html" \
        "/by-example/24-option-some-none.html:by-example/24-option-some-none.html" \
        "/by-example/71-kv-basic.html:by-example/71-kv-basic.html" \
        "/learn/01.html:learn/01.html" \
        "/install.sh:install.sh" \
        "/shared/spec.css:shared/spec.css"
    do
        path="${entry%%:*}"
        relfile="${entry#*:}"
        want=200
        [ -f "$static/$relfile" ] || want=404
        got="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL$path" 2>/dev/null || true)"
        if [ "$got" = "$want" ]; then
            echo "  OK   $path -> $got"
        else
            echo "  MAL  $path -> ${got:-sin respuesta} (esperaba $want)"
            checks_ok=0
        fi
    done

    if [ "$expect" = "anterior" ]; then
        got="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL/shared/nyx-design-system.css" 2>/dev/null || true)"
        if [ "$got" = "200" ]; then
            echo "  OK   /shared/nyx-design-system.css -> 200 (la hoja del legado sigue servida)"
        else
            echo "  MAL  /shared/nyx-design-system.css -> ${got:-sin respuesta} (esperaba 200)"
            checks_ok=0
        fi
    fi

    if [ "$expect" = "nuevo" ]; then
        local t1 t2 sin_products
        t1="$(mktemp)"; t2="$(mktemp)"
        curl -s --max-time 2 "$BASE_URL/" -o "$t1" 2>/dev/null || true
        curl -s --max-time 2 "$BASE_URL/es/" -o "$t2" 2>/dev/null || true
        sin_products="$(grep -L '#products' "$t1" "$t2" 2>/dev/null | wc -l | tr -d ' ')"
        if [ "$sin_products" = "2" ]; then
            echo "  OK   / y /es/ sin #products"
        else
            echo "  MAL  / y/o /es/ todavía tienen #products"
            checks_ok=0
        fi
        rm -f "$t1" "$t2"
    fi

    if [ "$checks_ok" != "1" ]; then
        echo "AVISO: alguna verificación post-intercambio no dio lo esperado (ver arriba). El intercambio de directorios YA se aplicó (mv --exchange es atómico)." >&2
        return 1
    fi
    return 0
}

cmd_status() {
    local site_abs="$1" d dir
    echo "== status: $SITE_ARG =="
    for d in static static-next; do
        dir="$site_abs/$d"
        if [ ! -e "$dir" ]; then
            echo "  $d/: no existe"
            continue
        fi
        if [ ! -d "$dir" ]; then
            echo "  $d/: existe pero NO es un directorio"
            continue
        fi
        echo "  $d/: directorio, $(site_generation_label "$(site_generation "$dir")")"
    done
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL/" 2>/dev/null || true)"
    if [ "$code" = "200" ]; then
        echo "  servidor en $BASE_URL: responde (200)"
    elif [ -n "$code" ] && [ "$code" != "000" ]; then
        echo "  servidor en $BASE_URL: responde con código $code"
    else
        echo "  servidor en $BASE_URL: no responde"
    fi
}

cmd_swap() {
    local site_abs="$1"
    local static="$site_abs/static" staticn="$site_abs/static-next"
    echo "== swap: $SITE_ARG =="

    mv_exchange_supported || abort "mv no soporta --exchange (coreutils < 9.7)."

    [ -d "$static" ]  || abort "$static no existe o no es un directorio."
    [ -d "$staticn" ] || abort "$staticn no existe o no es un directorio."

    local required rel
    required="index.html es/index.html docs/index.html es/docs/index.html by-example/index.html es/by-example/index.html shared/spec.css learn/index.html install.sh"
    for rel in $required; do
        [ -f "$staticn/$rel" ] || abort "falta $staticn/$rel — static-next/ no está completo."
    done

    # El swap PUBLICA lo que está en static-next/: sólo tiene sentido si esa es
    # una generación MÁS NUEVA que la publicada. Sin esta comparación, correr
    # `swap` dos veces seguidas despublicaba el sitio nuevo sin decir nada.
    local gen_now gen_next
    gen_now="$(site_generation "$static")"
    gen_next="$(site_generation "$staticn")"
    [ "$gen_next" -gt "$gen_now" ] || abort "static-next/ es $(site_generation_label "$gen_next") y static/ ya es $(site_generation_label "$gen_now") — el swap publicaría algo que no es más nuevo. ¿Querías « rollback »?"

    local site_rel dirty
    site_rel="$(site_relpath "$site_abs")"
    dirty="$(git -C "$REPO_ROOT" status --porcelain -- "$site_rel/static" "$site_rel/static-next" 2>&1)"
    if [ -n "$dirty" ]; then
        abort "hay cambios sin commitear en $site_rel/static o $site_rel/static-next:
$dirty"
    fi

    echo "-- check-content.sh $staticn --"
    if ! bash "$REPO_ROOT/scripts/check-content.sh" "$staticn"; then
        abort "scripts/check-content.sh $staticn no dio verde (ver salida arriba)."
    fi

    echo "precondiciones OK — intercambiando static/ <-> static-next/ ..."
    # -T: sin esto, como static-next/ ya existe, mv lo trata como directorio
    # DESTINO y mueve "static" ADENTRO de él (semántica normal de mv) en vez
    # de intercambiar los dos nombres. Con -T, DEST se trata como un nombre
    # normal (comportamiento confirmado en un directorio de prueba aparte).
    if ! (cd "$site_abs" && mv --exchange -T static static-next); then
        abort "mv --exchange falló (ver mensaje arriba) — no se aplicó ningún cambio."
    fi
    SWAPPED=1
    echo "hecho: static/ y static-next/ se intercambiaron (una sola syscall, atómica)."

    # rc≠0 si la verificación falló: el intercambio YA se aplicó (es atómico),
    # así que el código de salida es la única señal de «hay que ir a mirar». Sin
    # esto, `cutover-static.sh swap … && echo ok` daba verde falso con seis
    # links de la nav nueva en 404 (binario v1 todavía en producción).
    local verify_ok=0
    verify_site "nuevo" "$site_abs" || verify_ok=1

    echo
    echo "rollback: bash $SELF rollback $SITE_ARG"
    [ "$verify_ok" = "0" ] || exit 2
}

cmd_rollback() {
    local site_abs="$1"
    local static="$site_abs/static" staticn="$site_abs/static-next"
    echo "== rollback: $SITE_ARG =="

    mv_exchange_supported || abort "mv no soporta --exchange (coreutils < 9.7)."

    [ -d "$static" ]  || abort "$static no existe o no es un directorio."
    [ -d "$staticn" ] || abort "$staticn no existe o no es un directorio."

    # Espejo de la precondición del swap: revertir sólo tiene sentido si lo
    # guardado en static-next/ es una generación ANTERIOR a la publicada. Antes
    # de un swap la desigualdad va al revés, así que correr `rollback` por error
    # ahí no publica nada (que es lo que se busca: el rollback no puede
    # saltearse check-content.sh ni el chequeo de árbol commiteado del swap).
    local gen_now gen_prev
    gen_now="$(site_generation "$static")"
    gen_prev="$(site_generation "$staticn")"
    [ "$gen_prev" -lt "$gen_now" ] || abort "static-next/ es $(site_generation_label "$gen_prev") y static/ es $(site_generation_label "$gen_now") — no hay nada anterior que restaurar. ¿Ya se hizo el rollback, o nunca se hizo el swap?"

    echo "precondiciones OK — revirtiendo static/ <-> static-next/ ..."
    if ! (cd "$site_abs" && mv --exchange -T static static-next); then
        abort "mv --exchange falló (ver mensaje arriba) — no se aplicó ningún cambio."
    fi
    SWAPPED=1
    echo "hecho: static/ y static-next/ volvieron a intercambiarse."

    local verify_ok=0
    verify_site "anterior" "$site_abs" || verify_ok=1

    echo
    echo "para reintentar el swap: bash $SELF swap $SITE_ARG"
    [ "$verify_ok" = "0" ] || exit 2
}

case "$ACTION" in
    status)   cmd_status   "$SITE_ABS" ;;
    swap)     cmd_swap     "$SITE_ABS" ;;
    rollback) cmd_rollback "$SITE_ABS" ;;
esac
