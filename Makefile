# Makefile — nyx-sites (4 landings de producción)
# El toolchain Nyx vive fuera de este repo; se apunta vía NYX_HOME.
# El framework web es `std/serve` del core (absorción 2026-08-31): ya no hay
# lib vendorizada — el build resuelve `import "std/serve"` en $NYX_HOME/std.

NYX_HOME ?= /home/admin/nyx/lang
export NYX_HOME

SITES = nyxlang.com serve.nyxlang.com proxy.nyxlang.com edit.nyxlang.com

.PHONY: build-all smoke deploy status clean gen gen-test gen-check gen-docblocks check-content preview preview-stop

# ── Rediseño de nyxlang.com (rama redesign/spec-sheet) ──────────────────────
# El sitio se GENERA: gen.nx lee content/ + templates/ y escribe static-next/.
# Mientras dure el rediseño la salida vive al lado de static/ (producción) y
# recién al final se intercambian.
PORT ?= 13191

# gen.nx genera el sitio NUEVO; gen-site.sh además copia y parchea el
# LEGADO (learn/, by-example/, install.sh) que static-next tiene que seguir
# sirviendo mientras dure la fase 1 (T7, docs/design/...).
gen:
	bash scripts/gen-site.sh

# Suite del generador: los tests del tokenizador (src/gen/highlight.nx) + la
# muestra de la landing compilada y EJECUTADA de verdad.
#
# Ojo con la muestra: se verifica con `nyx <archivo>` y NO con `nyx check`,
# que no resuelve el prelude (ni los imports del proyecto) y da NYX1002 falsos
# — ver el reporte de la T1. `nyx <archivo>` compila, linkea y corre.
gen-test:
	cd nyxlang.com && nyx test
	cd nyxlang.com && nyx content/landing/sample.nx

# Falla (rc=1) si static-next/ no coincide con lo que gen.nx produce hoy.
gen-check:
	cd nyxlang.com && nyx gen.nx --out static-next --check

# Cada bloque de Nyx de la guía /docs se extrae de la salida generada y se
# compila de verdad. La guía promete que sus ejemplos andan; esto lo refuta o
# lo confirma. Depende de `gen`, porque lee static-next/, no content/.
gen-docblocks: gen
	cd nyxlang.com && sh ../scripts/check-doc-blocks.sh static-next

# Guardias del contenido PUBLICADO: productos/métricas/plataformas no
# soportadas/identidad vieja/anclas muertas/enlaces rotos/paridad EN-ES/
# voseo/salida al día. Corre el autotest de control positivo primero — si
# el instrumento no ve sus propios errores plantados, sale 2 sin evaluar
# nada más. ROOT sobreescribible: `make check-content ROOT=nyxlang.com/static`
# corre sobre el árbol que se va a servir (lo que hace deploy.sh).
ROOT ?= nyxlang.com/static-next
check-content:
	bash scripts/check-content.sh $(ROOT)

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
