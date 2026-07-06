# Makefile — nyx-sites (3 landings de producción)
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.

NYX_HOME ?= /home/admin/NyxLang
export NYX_HOME

SITES = nyxlang.com serve.nyxlang.com proxy.nyxlang.com

.PHONY: vendor build-all smoke deploy status clean

# Re-vendoriza nyx-serve desde ~/nyx-serve-stack (commitear el diff)
vendor:
	bash scripts/vendor_nyx_serve.sh

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
	      proxy.nyxlang.com/proxy-nyxlang-com */script.nx */script.ll
