# nyx-sites

Las 3 landing pages de producción del ecosistema Nyx,
cada una construida con `std/serve`, el framework web de la stdlib de Nyx
(absorbido de [nyx-serve](https://github.com/nyxlang-dev/nyx-serve) el 2026-08-31):

- **nyxlang.com** (:3001) — landing del lenguaje + Nyx Book + By-Example
- **serve.nyxlang.com** (:3003) — landing del framework nyx-serve
- **proxy.nyxlang.com** (:3005) — landing de nyx-proxy

```bash
make build-all  # compilar los 3 sites
make smoke      # verificación efímera sin tocar producción
make deploy     # deploy completo con restart verificado (sudo)
```

Requiere el toolchain Nyx (`NYX_HOME`, default `/home/admin/nyx/lang` — el
mismo que usa el `Makefile`).
Ver `CLAUDE.md` para reglas operativas.

## Cutover de nyxlang.com

El rediseño genera el sitio nuevo al lado del viejo (`static-next/` junto a
`static/`, ver `make gen`); el intercambio final es atómico, una sola
syscall (`mv --exchange`, coreutils ≥ 9.7), sin restart y sin ventana.

**El swap de la fase 2 usa EXACTAMENTE el mismo procedimiento.** No hay un
runbook aparte: la fase 2 (el recetario `/by-example` generado, en vez de la
copia parcheada del recetario viejo) deja `static-next/` como el sitio COMPLETO
v2 — landing + guía + recetario + «The Nyx Book» legado + `shared/` con las dos
hojas + `install.sh` + `logo.png` — y se publica con los mismos siete pasos de
abajo. `cutover-static.sh` razona por GENERACIÓN de sitio (fase 2 > fase 1 >
sitio viejo), así que `swap` exige que `static-next/` sea más nuevo que lo
publicado y `rollback` que sea más viejo: correr cualquiera de los dos en el
estado equivocado aborta sin tocar nada.

Después del swap de la fase 2, `static-next/` queda con **el sitio de la fase
1** — ese es el rollback disponible, y por eso la limpieza (borrar el recetario
legado, `DRIFT.md`, el modo `--drift` de `sync-recipes.sh`) NO se hace en el
mismo paso: se hace cuando el sitio v2 ya demostró estar bien, aceptando que
hasta entonces el rollback vuelve a un sitio que todavía nombra productos en
`/by-example/`.

### Runbook, en orden

```
1. make verify                                  # gen + los 32 bloques de la guía compilan + check-content
   make gen-test                                #   tests del generador + la muestra de la landing
2. make deploy                                  # binario v2 (T5, NYX_STATIC_ROOT) con la raíz por default
   curl -s -o /dev/null -w '%{http_code}' localhost:3001/docs/   # 404 limpio, / sin cambios
3. git merge --ff-only <rama>                   # 0 archivos tocados bajo static/
                                                #   fase 1: redesign/spec-sheet · fase 2: redesign/by-example
4. make cutover-status                          # static = generación publicada, static-next = la nueva
5. bash scripts/cutover-static.sh swap nyxlang.com
6. curls contra https://nyxlang.com             # el gateway drena keep-alives stale (~15 requests)
7. commit — y RECIÉN ACÁ el release del monorepo / el sync del mirror público
8. bash /home/admin/nyx/lang/scripts/sync_to_public.sh core     # + push del mirror público
   bash scripts/sync-recipes.sh --check-mirror                  # 0 diferencias tras el push
```

**Paso 8, no opcional (fase 2):** los 69 enlaces «Source →» del recetario NO
apuntan al monorepo privado sino al mirror público
(`github.com/nyxlang-dev/nyx/blob/main/examples/by-example/<slug>.nx`), y ese
mirror puede tener recetas viejas — hoy tiene 8, cinco de ellas con código que
ya no compila. Sin este paso, en el instante del swap el sitio muestra un
programa y su enlace ofrece otro: el mismo drift que la fase 2 existe para
matar, movido un salto más allá. `sync_to_public.sh core` copia
`examples/by-example/*.nx` (líneas 116-117); `sync-recipes.sh --check-mirror`
compara y avisa con ⚠ (sale 0 siempre: antes del paso 8 la diferencia es el
estado esperado, y un clon sin el mirror al lado no puede comparar nada). El
check L de `check-content.sh` lo corre en cada pasada y lo reporta como aviso.

**Gate del paso 7 (no es una recomendación, es el orden):** ningún release
del monorepo ni sync del mirror público antes del swap. `scripts/install.sh`,
`LLM.md`, `scripts/build-release.sh`, `README.md` y `docs/GETTING_STARTED.md`
del monorepo del lenguaje ya apuntan a `https://nyxlang.com/docs/` en `main`
(T8, mergeado) y no queda ninguna referencia a `/learn/`. Hasta que el swap
esté hecho, esa URL da 404: publicar un release antes manda al usuario recién
instalado a una página que no existe.

El paso 2 va antes del 5 y no al revés: el binario v1 no tiene la ruta
`/docs/`, así que un swap con v1 todavía en producción deja seis links de la
nav nueva en 404. Desde la review final eso además hace salir a `swap` con
rc=2 (el intercambio ya se aplicó — es atómico — y el rc es la señal de «hay
que ir a mirar»), así que `cutover-static.sh swap … && …` no puede encadenar sobre
un cutover a medio verificar.

### Los tres subcomandos

```bash
make cutover-status                                          # solo lectura, no toca nada
bash scripts/cutover-static.sh swap nyxlang.com               # precondiciones + mv --exchange + verificación
bash scripts/cutover-static.sh rollback nyxlang.com           # revierte (el mismo mv --exchange, es su propio inverso)
```

`swap` aborta sin tocar nada si falta algo en `static-next/`, si su
generación no es más nueva que la publicada, si hay cambios sin commitear en
`static/`/`static-next/`, o si `scripts/check-content.sh static-next` no da
verde. `rollback` aborta si la generación de `static-next/` no es ANTERIOR a
la de `static/` — o sea, antes del swap no hace nada (correrlo por error ahí
no publica el sitio nuevo). `PORT` (default 3001) y `BASE_URL` controlan contra qué servidor se
verifica después del intercambio; sin servidor escuchando, el script lo avisa
y omite los curls (no es un fallo, y sale 0). Si hay servidor y alguna
verificación falla, sale 2. No hay target de Makefile para `swap`/`rollback`
— se invocan a mano con la ruta del sitio explícita para que nadie los
dispare sin querer.
