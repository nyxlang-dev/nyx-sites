# DRIFT del recetario — código publicado vs. `.nx` del monorepo

Generado por `bash scripts/sync-recipes.sh --drift`. NO se edita a mano.

Compara, por cada receta publicada, el código que muestra el recetario VIEJO
(`static-next/by-example/<slug>.html`, des-escapado y sin los `<span>` del
resaltado) contra `examples/by-example/<slug>.nx` del monorepo, que es la fuente de
verdad y lo que se publica de ahora en más.

Que una receta figure acá significa que **la prosa del sidecar puede estar describiendo
código que ya no existe**: es la lista de trabajo de la revisión de prosa (T10). Que NO
figure significa que el código publicado seguía siendo idéntico al del monorepo.

| receta | líneas (publicado → `.nx`) | diferencia |
|---|---|---|
| `41-base64` | 22 → 25 | +3 / -0 |
| `42-url-encode` | 22 → 27 | +5 / -0 |
| `43-toml-config` | 27 → 32 | +5 / -0 |
| `44-msgpack` | 26 → 31 | +6 / -1 |
| `45-dns-resolve` | 17 → 21 | +4 / -0 |
| `46-tcp-client` | 26 → 32 | +6 / -0 |
| `47-tcp-server` | 26 → 29 | +3 / -0 |
| `48-udp-socket` | 20 → 24 | +4 / -0 |
| `49-http-get` | 22 → 25 | +3 / -0 |
| `50-http-post` | 25 → 27 | +3 / -1 |
| `51-http-server` | 23 → 31 | +9 / -1 |
| `52-http-middleware` | 30 → 35 | +5 / -0 |
| `53-websocket` | 20 → 24 | +4 / -0 |
| `55-sqlite` | 30 → 36 | +7 / -1 |
| `56-csv-write` | 27 → 33 | +6 / -0 |
| `57-mutex` | 31 → 35 | +5 / -1 |
| `62-semaphore` | 32 → 37 | +5 / -0 |
| `70-shebang-script` | 26 → 25 | +2 / -3 |
| `101-file-errors-two-tier` | — | receta nueva: no existe en el recetario viejo |
| `102-template-flask-style` | — | receta nueva: no existe en el recetario viejo |

- recetas publicadas: 71
- con drift: 18
- idénticas: 51
- sin página vieja (recetas nuevas): 2
