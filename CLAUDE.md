# nyx-sites — Guía para Claude Code

## Qué es este repo

**Repo PRIVADO** con las 3 landing pages de producción del ecosistema Nyx,
extraídas del monorepo NyxLang (split #6, 2026-07-06). Cada site es un
proyecto `nyx build` independiente que consume la lib **nyx-serve**
(vendorizada y COMMITEADA en `<site>/packages/nyx-serve/`).

| Site | Binario | Unit systemd | Puerto |
|---|---|---|---|
| nyxlang.com/ | nyxlang-com | nyx-landing-main | :3001 |
| serve.nyxlang.com/ | serve-nyxlang-com | nyx-serve-web | :3003 |
| proxy.nyxlang.com/ | proxy-nyxlang-com | nyx-proxy-web | :3005 |

El gateway HTTPS (:443, `NyxLang/services/gateway` hasta el split #7) los
rutea por SNI. nyxkv.com vive aparte en `~/nyx-kv-stack`.

## Comandos

```bash
make vendor      # re-vendoriza nyx-serve desde ~/nyx-serve-stack (commitear diff)
make build-all   # nyx build en los 3 sites (NYX_HOME → toolchain)
make smoke       # build + daemon efímero por site en :131xx + curl 200
make deploy      # build + smoke + units + restart secuencial verificado (sudo)
make status      # is-active de las 3 units
```

## Reglas

- ⛔ **NUNCA ejecutar los binarios en foreground** en una sesión — son
  servidores bloqueantes. El smoke los corre en background y los baja.
- ⛔ **Este repo NO se sincroniza a ningún repo público** (paths de
  servidor, contenido de producción).
- **Vendoring COMMITEADO**: `packages/nyx-serve/` va al git de este repo
  (build determinista sin red; pin explícito de la versión de la lib).
  Actualizar SOLO con `make vendor` + commit del diff. Decisión 2026-07-06.
- `static/` se resuelve relativo al cwd → los units fijan
  `WorkingDirectory=<site>`; el smoke hace `cd` al dir del site.
- Restart de producción: siempre vía `make deploy` (smoke ANTES de tocar
  units; orden serve-web → proxy-web → landing-main; aborta al primer
  fallo). Rollback: binario anterior sigue en el dir hasta el próximo build.
- Contenido de las landings: NO inventar benchmarks ni features no
  released — reconciliar con los docs del monorepo.

## Relación con otros repos

- **~/nyx-serve-stack**: la lib que estos sites consumen (fuente del vendor).
- **NyxLang** (monorepo): gateway + certs Let's Encrypt + `std/` del
  lenguaje. El deploy del gateway sigue siendo `NyxLang/scripts/deploy.sh`.
- **~/nyx-kv-stack**: nyxkv.com (:3002) y su dashboard (:3007).
