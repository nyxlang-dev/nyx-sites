# Makefile — nyx-sites (4 landings de producción)
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.
# El framework web es `std/serve` del core (absorción 2026-08-31): ya no hay
# lib vendorizada — el build resuelve `import "std/serve"` en $NYX_HOME/std.

NYX_HOME ?= /home/admin/nyx/lang
export NYX_HOME

SITES = nyxlang.com serve.nyxlang.com proxy.nyxlang.com edit.nyxlang.com

.PHONY: build-all smoke deploy status clean

build-all:
	@for s in $(SITES); do \
		echo "=== $$s ==="; \
		(cd $$s && nyx build) || exit 1; \
	done

# Smoke efímero por site en puertos 131xx (no toca producción)
smoke: build-all
	bash scripts/smoke.sh

# Build + smoke + instalar units + restart secuencial verificado (sudo)
deploy:
	bash scripts/deploy.sh

status:
	@systemctl is-active nyx-landing-main nyx-serve-web nyx-proxy-web

clean:
	rm -f nyxlang.com/nyxlang-com serve.nyxlang.com/serve-nyxlang-com \
	      proxy.nyxlang.com/proxy-nyxlang-com edit.nyxlang.com/edit-nyxlang-com */script.nx */script.ll
