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
