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

Requiere el toolchain Nyx (`NYX_HOME`, default `/home/admin/NyxLang`).
Ver `CLAUDE.md` para reglas operativas.

## Cutover de nyxlang.com

El rediseño genera el sitio nuevo al lado del viejo (`static-next/` junto a
`static/`, ver `make gen`); el intercambio final es atómico, una sola
syscall (`mv --exchange`, coreutils ≥ 9.7), sin restart y sin ventana:

```bash
make cutover-status                                          # solo lectura, no toca nada
bash scripts/cutover-static.sh swap nyxlang.com               # precondiciones + mv --exchange + verificación
bash scripts/cutover-static.sh rollback nyxlang.com           # revierte (el mismo mv --exchange, es su propio inverso)
```

`swap` aborta sin tocar nada si falta algo en `static-next/`, si hay
cambios sin commitear en `static/`/`static-next/`, o si
`scripts/check-content.sh static-next` no da verde. `PORT` (default 3001)
y `BASE_URL` controlan contra qué servidor se verifica después del
intercambio; sin servidor escuchando, el script lo avisa y omite los curls
(no es un fallo). No hay target de Makefile para `swap`/`rollback` — se
invocan a mano con la ruta del sitio explícita para que nadie los dispare
sin querer.
