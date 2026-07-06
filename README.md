# nyx-sites

Repo privado con las 3 landing pages de producción del ecosistema Nyx,
cada una construida con [nyx-serve](https://github.com/nyxlang-dev/nyx-serve):

- **nyxlang.com** (:3001) — landing del lenguaje + Nyx Book + By-Example
- **serve.nyxlang.com** (:3003) — landing del framework nyx-serve
- **proxy.nyxlang.com** (:3005) — landing de nyx-proxy

```bash
make vendor     # actualizar la lib vendorizada desde ~/nyx-serve-stack
make build-all  # compilar los 3 sites
make smoke      # verificación efímera sin tocar producción
make deploy     # deploy completo con restart verificado (sudo)
```

Requiere el toolchain Nyx (`NYX_HOME`, default `/home/admin/NyxLang`).
Ver `CLAUDE.md` para reglas operativas.
