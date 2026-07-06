# nyx-sites — Project State

**Extraído del monorepo**: 2026-07-06 (split #6) — antes `NyxLang/sites/`.
**Naturaleza**: repo único con los 3 landings de producción. PÚBLICO en
GitHub (decisión Ottavio 2026-07-06 al crearlo — el contenido ya es web
pública; CLAUDE/PROJECT_STATE son metadoc operativa, cuidar no volcar
datos sensibles acá).
**Estado**: en producción (units nyx-landing-main :3001, nyx-serve-web
:3003, nyx-proxy-web :3005, detrás del gateway :443 por SNI).

## Decisiones

- **Repo único, no 3 repos** (Ottavio, 2026-07-06): los sites comparten
  patrón (nyx-serve + static/) y deploy; un solo repo baja el overhead.
- **Sites como proyecto solo, NO dentro del serve-stack** (Ottavio,
  2026-07-06): son consumers del framework, igual que cualquier usuario;
  el stack queda solo con la lib.
- **Vendoring COMMITEADO** de `packages/nyx-serve/` (a diferencia del
  monorepo, que lo gitignoraba y copiaba "solo si falta" — dejaba copias
  stale): build determinista sin red y pin explícito. `make vendor`
  actualiza; el diff se commitea. Si algún día molesta, pasar al patrón
  kv-stack (gitignored + re-vendor en deploy) es 1 línea de .gitignore.
- **Units con paths propios**: `/home/admin/nyx-sites/<site>/` (antes
  `NyxLang/sites/`). Cutover hecho en el split #6 sin downtime.

## Estado del contenido

- nyxlang.com: landing + Nyx Book + By-Example (100 recetas EN + 101 ES).
  Badge de versión: v0.18.1 (actualizado 2026-07-04) — revisar al taggear.
- serve.nyxlang.com / proxy.nyxlang.com: landings de las libs; proxy
  anuncia WebSocket proxying (v0.17).

## Deuda / pendientes

- Los sites se sirven de disco sin reload — cambios de static/ requieren
  restart de la unit (o nada si es contenido que el binario relee).
- Badge de versión de nyxlang.com se actualiza a mano en cada release.
- Split #7 pendiente en el monorepo: el gateway será proyecto solo; los
  units de estos sites no cambian con eso.
