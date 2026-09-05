#!/usr/bin/env bash
# extract-by-example-prose.sh — extrae la prosa del recetario VIEJO a sidecars.
#
# ⚠ ESTE SCRIPT SE CORRE UNA SOLA VEZ (fase 2 del rediseño de nyxlang.com).
#
# No es parte del build ni de ninguna guardia: su única razón de existir es que
# la prosa de las 100 recetas (intro, salida, explicación, título y blurb, en
# EN y ES) sólo existía dentro del HTML escrito a mano de `static-next/`. Una
# vez extraída a `content/by-example/<slug>.{en,es}.html`, la fuente de verdad
# pasa a ser el sidecar y este script queda como registro de PROCEDENCIA: si
# alguien pregunta de dónde salió un párrafo, la respuesta es reproducible.
#
# POR ESO USA python3, y es el ÚNICO script de este repo que lo hace. Los
# scripts repetibles (`sync-recipes.sh`, `check-content.sh`, `gen-site.sh`,
# `smoke.sh`) son bash sin dependencias, porque corren en cada build y en cada
# release. Éste corre una vez, sobre HTML escrito a mano con anidamiento y
# entidades, y ahí un extractor de texto con regex sobre bytes en bash sería
# más frágil que el resultado que produce. Es idempotente: volver a correrlo
# sobre el mismo HTML viejo reescribe los mismos bytes.
#
# Uso:
#   bash scripts/extract-by-example-prose.sh [--old-root DIR] [--dry-run]
#
#   --old-root DIR   raíz del sitio VIEJO (default: nyxlang.com/static-next).
#                    El HTML pristino también se puede sacar de git:
#                    `git show d4f6bef:nyxlang.com/static/by-example/<archivo>`.
#   --dry-run        informa lo que haría, sin escribir ningún archivo.
#
# Alcance: las recetas de `content/by-example/recipes.toml` con
# `excluded = "0"` y `sidecar = "1"` (69: 01-70 menos 54-resp-protocol). Las
# recetas 101 y 102 NO tienen página vieja — sus sidecars nacen como STUB, y
# los siembra `scripts/sync-recipes.sh`, no este script: acá no se inventa
# prosa que no existía.
#
# Formato del sidecar (lo consume el generador de la T11):
#
#   <!-- title: … | blurb: … -->
#   <section data-part="intro">…</section>
#   <section data-part="output">…</section>
#   <section data-part="explanation">…</section>
#
#   · La primera línea son los metadatos. `title` sale del <h1> de la página y
#     `blurb` de la tarjeta del índice viejo, localizada por el href de la
#     receta, cada uno en su idioma. Se guardan con el escapado del original
#     (`File Read &amp; Write`) y el blurb conserva sus <code> interiores.
#     Verificado antes de elegir el separador: ningún título ni blurb de las 69
#     recetas contiene `|`, `--` ni saltos de línea.
#   · intro y explanation conservan el HTML interior tal cual (sólo <p>, <code>,
#     <em> y <strong> en las 69 × 2), un elemento por línea, sin sangría.
#   · output es el contenido del <pre class="output"> ESCAPADO tal cual estaba;
#     va sin <pre> porque el panel lo pone el template. CONVENCIÓN: el salto de
#     línea que sigue a <section …> y el que precede a </section> son
#     delimitadores, no contenido. Es seguro porque ninguna de las 138 salidas
#     del recetario viejo empieza ni termina con una línea en blanco (se
#     verifica acá abajo, y el script aborta si alguna lo hiciera).
#   · El bloque de código NO se copia: viene del .nx del monorepo, que sincroniza
#     `scripts/sync-recipes.sh`.
#
# Marcadores del HTML viejo (relevados sobre las 100 páginas × 2 idiomas antes
# de escribir una línea de este script): EN usa <h2>Code</h2>, <h2>Output</h2>,
# <h2>Explanation</h2>; ES usa <h2>Código</h2>, <h2>Salida</h2>,
# <h2>Explicación</h2>. Los 100 archivos de cada idioma tienen los tres. Si en
# alguna receta un marcador NO aparece, este script NO rellena nada: la
# reporta al final bajo «FALTANTES» y deja el sidecar sin esa sección.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
SITE="$ROOT/nyxlang.com"
OLD_ROOT="$SITE/static-next"
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --old-root) OLD_ROOT="$2"; shift 2 ;;
        --dry-run)  DRY=1; shift ;;
        -h|--help)  sed -n '2,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "extract-by-example-prose: argumento desconocido: $1" >&2; exit 1 ;;
    esac
done

[ -d "$OLD_ROOT/by-example" ] || { echo "extract-by-example-prose: falta $OLD_ROOT/by-example" >&2; exit 1; }
command -v python3 >/dev/null || { echo "extract-by-example-prose: hace falta python3 (script de una sola vez)" >&2; exit 1; }

OLD_ROOT="$OLD_ROOT" SITE="$SITE" DRY="$DRY" python3 - <<'PYEOF'
import os, re, sys

old_root = os.environ["OLD_ROOT"]
site     = os.environ["SITE"]
dry      = os.environ["DRY"] == "1"

catalog = os.path.join(site, "content", "by-example", "recipes.toml")
out_dir = os.path.join(site, "content", "by-example")

# ── alcance: recipes.toml, sin depender de un parser TOML ───────────────────
# El catálogo es plano y regular (una tabla [rNN] por receta, un `clave = "…"`
# por línea); leerlo con dos regex acá es honesto y no arrastra dependencias.
tables = {}
section = None
for line in open(catalog, encoding="utf-8"):
    line = line.strip()
    if line.startswith("#") or not line:
        continue
    m = re.match(r'^\[([^\]]+)\]$', line)
    if m:
        section = m.group(1)
        tables[section] = {}
        continue
    m = re.match(r'^([a-z_]+)\s*=\s*"(.*)"$', line)
    if m and section:
        tables[section][m.group(1)] = m.group(2)

recipes = [(int(t["num"]), t["slug"]) for t in tables.values()
           if t.get("excluded") == "0" and t.get("sidecar") == "1"]
recipes.sort()
if not recipes:
    sys.exit("extract-by-example-prose: recipes.toml no declaró ninguna receta con sidecar = \"1\"")

LANGS = (
    # (lang, subdir del sitio viejo, prefijo del href en el índice, h2 code, h2 output, h2 explanation)
    ("en", "by-example",    "/by-example/",    "Code",   "Output", "Explanation"),
    ("es", "es/by-example", "/es/by-example/", "Código", "Salida", "Explicación"),
)

def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def cards(index_html, href_prefix):
    """slug → (title, blurb) de las tarjetas del índice viejo, por href."""
    pat = (r'<a href="' + re.escape(href_prefix) + r'([^"]+)\.html" class="recipe-card">\s*'
           r'<div class="recipe-num">[^<]*</div>\s*'
           r'<div class="recipe-title">(.*?)</div>\s*'
           r'<div class="recipe-desc">(.*?)</div>')
    return {m.group(1): (m.group(2).strip(), m.group(3).strip())
            for m in re.finditer(pat, index_html, re.S)}

def block(html, start_re, end_re):
    m = re.search(start_re + r'(.*?)' + end_re, html, re.S)
    return m.group(1) if m else None

def tidy(fragment):
    """Un elemento de bloque por línea, sin sangría; se conserva el HTML interior."""
    text = fragment.strip()
    text = re.sub(r'>\s*\n\s*<', '>\n<', text)
    return "\n".join(l.strip() for l in text.split("\n") if l.strip())

missing = []      # (slug, lang, qué faltó)
counts  = {}      # (slug, lang) → (párrafos de intro, líneas de salida, párrafos de explicación)
written = 0

for lang, subdir, href_prefix, h_code, h_out, h_expl in LANGS:
    base = os.path.join(old_root, subdir)
    index_path = os.path.join(base, "index.html")
    if not os.path.exists(index_path):
        sys.exit("extract-by-example-prose: falta el índice viejo %s" % index_path)
    card = cards(read(index_path), href_prefix)

    for num, slug in recipes:
        page = os.path.join(base, slug + ".html")
        if not os.path.exists(page):
            missing.append((slug, lang, "la página vieja no existe"))
            continue
        html = read(page)

        title = block(html, r'<h1>', r'</h1>')
        if title is None:
            missing.append((slug, lang, "<h1>"))
            title = ""
        title = " ".join(title.split())

        if slug in card:
            blurb = " ".join(card[slug][1].split())
        else:
            missing.append((slug, lang, "tarjeta del índice (href %s%s.html)" % (href_prefix, slug)))
            blurb = ""

        intro = block(html, r'</h1>', r'<h2>' + h_code + r'</h2>')
        if intro is None:
            missing.append((slug, lang, "intro (entre </h1> y <h2>%s</h2>)" % h_code))
        output = block(html, r'<h2>' + h_out + r'</h2>\s*<pre class="output">', r'</pre>')
        if output is None:
            missing.append((slug, lang, '<pre class="output"> bajo <h2>%s</h2>' % h_out))
        expl = block(html, r'<h2>' + h_expl + r'</h2>', r'<div class="book-nav">')
        if expl is None:
            missing.append((slug, lang, "explicación (entre <h2>%s</h2> y book-nav)" % h_expl))

        for field, value in (("title", title), ("blurb", blurb)):
            if "|" in value or "--" in value:
                sys.exit("extract-by-example-prose: %s/%s: el %s contiene «|» o «--» y rompería "
                         "la línea de metadatos: %r" % (slug, lang, field, value))

        parts = ['<!-- title: %s | blurb: %s -->' % (title, blurb)]
        n_intro = n_expl = n_out = 0
        if intro is not None:
            body = tidy(intro)
            n_intro = len(re.findall(r'<p[ >]', body))
            parts.append('<section data-part="intro">\n%s\n</section>' % body)
        if output is not None:
            if output != output.strip("\n"):
                sys.exit("extract-by-example-prose: %s/%s: la salida empieza o termina con una "
                         "línea en blanco y la convención de delimitadores la perdería" % (slug, lang))
            n_out = len(output.split("\n"))
            parts.append('<section data-part="output">\n%s\n</section>' % output)
        if expl is not None:
            body = tidy(expl)
            n_expl = len(re.findall(r'<p[ >]', body))
            parts.append('<section data-part="explanation">\n%s\n</section>' % body)

        counts[(slug, lang)] = (n_intro, n_out, n_expl)
        dest = os.path.join(out_dir, "%s.%s.html" % (slug, lang))
        if not dry:
            with open(dest, "w", encoding="utf-8") as fh:
                fh.write("\n".join(parts) + "\n")
        written += 1

# ── informe ────────────────────────────────────────────────────────────────
print("extract-by-example-prose: %d sidecar(s) %s (%d recetas × 2 idiomas)"
      % (written, "que se escribirían" if dry else "escritos", len(recipes)))

print("")
print("receta                          intro/salida/explicación (EN)   (ES)")
for num, slug in recipes:
    en = counts.get((slug, "en"))
    es = counts.get((slug, "es"))
    fmt = lambda c: "%d/%d/%d" % c if c else "—"
    flag = "" if (en and es and en[0] == es[0] and en[2] == es[2]) else "   ← EN/ES no coinciden"
    print("  %-30s %-14s %-14s%s" % (slug, fmt(en), fmt(es), flag))

print("")
if missing:
    print("FALTANTES (%d) — marcador no encontrado, NADA se rellenó:" % len(missing))
    for slug, lang, what in missing:
        print("  %s [%s]: %s" % (slug, lang, what))
    sys.exit(1)
print("FALTANTES: ninguno — los tres marcadores aparecieron en las %d recetas × 2 idiomas."
      % len(recipes))
PYEOF
