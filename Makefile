# Makefile — nyx-sites (4 landings de producción)
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.
# El framework web es `std/serve` del core (absorción 2026-08-31): ya no hay
# lib vendorizada — el build resuelve `import "std/serve"` en $NYX_HOME/std.

NYX_HOME ?= /home/admin/nyx/lang
export NYX_HOME

SITES = nyxlang.com serve.nyxlang.com proxy.nyxlang.com edit.nyxlang.com

.PHONY: build-all smoke deploy status clean gen gen-check preview preview-stop

# ── Rediseño de nyxlang.com (rama redesign/spec-sheet) ──────────────────────
# El sitio se GENERA: gen.nx lee content/ + templates/ y escribe static-next/.
# Mientras dure el rediseño la salida vive al lado de static/ (producción) y
# recién al final se intercambian.
PORT ?= 13191

gen:
	cd nyxlang.com && nyx gen.nx --out static-next

# Falla (rc=1) si static-next/ no coincide con lo que gen.nx produce hoy.
gen-check:
	cd nyxlang.com && nyx gen.nx --out static-next --check

# Preview local en background (nunca en foreground: bloquea la sesión).
# NYX_STATIC_ROOT lo implementa la T5; hasta entonces el binario sirve
# static/ y este target solo levanta el servidor.
preview:
	cd nyxlang.com && NYX_STATIC_ROOT=static-next PORT=$(PORT) nohup ./nyxlang-com > /tmp/nyxlang-preview.log 2>&1 & echo $$! > nyxlang.com/.preview.pid

preview-stop:
	@if [ -f nyxlang.com/.preview.pid ]; then \
		kill "$$(cat nyxlang.com/.preview.pid)" 2>/dev/null || true; \
		rm -f nyxlang.com/.preview.pid; \
		echo "preview detenido"; \
	else \
		echo "no hay preview corriendo"; \
	fi

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
