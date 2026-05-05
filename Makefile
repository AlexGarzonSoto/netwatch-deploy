# ──────────────────────────────────────────────────────────────────────────────
#  NetWatch — Comandos de gestión
#  Uso: make <comando>   Ejemplo: make iniciar
# ──────────────────────────────────────────────────────────────────────────────

SHELL := /bin/bash

.DEFAULT_GOAL := ayuda
.PHONY: ayuda configurar iniciar detener estado logs reiniciar limpiar abrir verificar

VERDE    := \033[0;32m
AMARILLO := \033[0;33m
ROJO     := \033[0;31m
RESET    := \033[0m
NEGRITA  := \033[1m

# ── Ayuda ─────────────────────────────────────────────────────────────────────
ayuda:
	@echo ""
	@echo "$(NEGRITA)NetWatch — Comandos disponibles$(RESET)"
	@echo "────────────────────────────────────────────────"
	@echo "  $(VERDE)make configurar$(RESET)   Primera vez: crea el archivo de configuración"
	@echo "  $(VERDE)make iniciar$(RESET)      Arranca NetWatch (descarga imágenes de Docker Hub)"
	@echo "  $(VERDE)make detener$(RESET)      Para NetWatch (los datos se conservan)"
	@echo "  $(VERDE)make estado$(RESET)       Muestra si todos los servicios funcionan"
	@echo "  $(VERDE)make logs$(RESET)         Muestra los mensajes internos en tiempo real"
	@echo "  $(VERDE)make reiniciar$(RESET)    Para y vuelve a arrancar NetWatch"
	@echo "  $(VERDE)make abrir$(RESET)        Abre el dashboard en el navegador"
	@echo "  $(ROJO)make limpiar$(RESET)      Borra TODO incluyendo datos guardados"
	@echo "────────────────────────────────────────────────"
	@echo "  Guía paso a paso: docs/INICIO-RAPIDO.md"
	@echo ""

# ── Configurar — solo se ejecuta la primera vez ───────────────────────────────
configurar:
	@echo ""
	@echo "$(NEGRITA)Paso 1/2 — Verificando requisitos...$(RESET)"
	@if ! command -v docker &> /dev/null; then \
		echo "$(ROJO)✗ Docker no está instalado.$(RESET)"; \
		echo "  Instálalo desde: https://docs.docker.com/engine/install/"; \
		exit 1; \
	fi
	@echo "$(VERDE)✓ Docker encontrado: $$(docker --version)$(RESET)"
	@if ! docker compose version &> /dev/null; then \
		echo "$(ROJO)✗ Docker Compose no está disponible.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(VERDE)✓ Docker Compose encontrado$(RESET)"
	@echo ""
	@echo "$(NEGRITA)Paso 2/2 — Creando archivo de configuración (.env)...$(RESET)"
	@if [ -f .env ]; then \
		echo "$(AMARILLO)! Ya existe un archivo .env — no se sobreescribe.$(RESET)"; \
		echo "  Si quieres empezar de cero: elimina .env y vuelve a ejecutar 'make configurar'"; \
	else \
		cp .env.example .env; \
		JWT=$$(openssl rand -hex 64); \
		JWT_REFRESH=$$(openssl rand -hex 64); \
		sed -i "s|REEMPLAZA_CON_CADENA_ALEATORIA_DE_64_CHARS_usa_openssl_rand_hex_64|$$JWT|" .env; \
		sed -i "s|REEMPLAZA_CON_OTRA_CADENA_64_CHARS_usa_openssl_rand_hex_64_diferente|$$JWT_REFRESH|" .env; \
		echo "$(VERDE)✓ Archivo .env creado con claves de seguridad generadas automáticamente$(RESET)"; \
	fi
	@echo ""
	@echo "$(VERDE)$(NEGRITA)✓ Configuración lista.$(RESET)"
	@echo ""
	@echo "  Próximo paso:"
	@echo "    $(NEGRITA)make iniciar$(RESET)"
	@echo ""

# ── Iniciar ───────────────────────────────────────────────────────────────────
iniciar: verificar
	@echo ""
	@echo "$(NEGRITA)Iniciando NetWatch...$(RESET)"
	@echo "  (La primera vez tarda 2-5 minutos descargando imágenes de Docker Hub)"
	@echo ""
	docker compose up -d
	@echo ""
	@echo "$(VERDE)$(NEGRITA)✓ NetWatch arrancado.$(RESET)"
	@echo ""
	@echo "  Espera 2 minutos y luego accede a:"
	@echo "    $(NEGRITA)Dashboard:  http://localhost:3000$(RESET)"
	@echo "    Métricas:   http://localhost:3001  (usuario: admin)"
	@echo ""
	@echo "  Credenciales iniciales:"
	@echo "    Usuario:    admin@netwatch.local"
	@echo "    Contraseña: NetWatch2024!"
	@echo ""
	@echo "  Para ver si todo está funcionando: $(NEGRITA)make estado$(RESET)"
	@echo ""

# ── Detener ───────────────────────────────────────────────────────────────────
detener:
	@echo ""
	@echo "$(NEGRITA)Deteniendo NetWatch...$(RESET)"
	docker compose down
	@echo ""
	@echo "$(VERDE)✓ NetWatch detenido. Los datos guardados se conservan.$(RESET)"
	@echo "  Para volver a arrancar: $(NEGRITA)make iniciar$(RESET)"
	@echo ""

# ── Estado ────────────────────────────────────────────────────────────────────
estado:
	@echo ""
	@echo "$(NEGRITA)Estado de los servicios de NetWatch$(RESET)"
	@echo "────────────────────────────────────────────────"
	docker compose ps
	@echo ""
	@echo "  Los servicios en verde (running/healthy) están funcionando correctamente."
	@echo "  Si alguno aparece en rojo, ejecuta: $(NEGRITA)make logs$(RESET)"
	@echo ""

# ── Logs ──────────────────────────────────────────────────────────────────────
logs:
	@echo ""
	@echo "$(NEGRITA)Mensajes internos de NetWatch$(RESET) (Ctrl+C para salir)"
	@echo "────────────────────────────────────────────────"
	docker compose logs -f --tail=50

# ── Reiniciar ─────────────────────────────────────────────────────────────────
reiniciar:
	@echo ""
	@echo "$(NEGRITA)Reiniciando NetWatch...$(RESET)"
	docker compose restart
	@echo ""
	@echo "$(VERDE)✓ NetWatch reiniciado.$(RESET)"
	@echo "  Espera 1 minuto y accede a: $(NEGRITA)http://localhost:3000$(RESET)"
	@echo ""

# ── Abrir en navegador ────────────────────────────────────────────────────────
abrir:
	@echo "Abriendo NetWatch en el navegador..."
	@if command -v xdg-open &> /dev/null; then \
		xdg-open http://localhost:3000; \
	elif command -v open &> /dev/null; then \
		open http://localhost:3000; \
	else \
		echo "Abre esta dirección en tu navegador: http://localhost:3000"; \
	fi

# ── Limpiar — borra todo, incluidos los datos ─────────────────────────────────
limpiar:
	@echo ""
	@echo "$(ROJO)$(NEGRITA)¡ADVERTENCIA!$(RESET)"
	@echo "$(ROJO)  Esto borrará NetWatch Y TODOS LOS DATOS GUARDADOS$(RESET)"
	@echo "  (eventos detectados, alertas, usuarios, historial)"
	@echo ""
	@read -p "  ¿Estás seguro? Escribe 'si' para confirmar: " confirmacion; \
	if [ "$$confirmacion" = "si" ]; then \
		docker compose down -v --remove-orphans; \
		echo ""; \
		echo "$(VERDE)✓ NetWatch eliminado completamente.$(RESET)"; \
		echo "  Para empezar de nuevo: $(NEGRITA)make configurar && make iniciar$(RESET)"; \
	else \
		echo "$(AMARILLO)Cancelado. No se borró nada.$(RESET)"; \
	fi
	@echo ""

# ── Verificación interna ───────────────────────────────────────────────────────
verificar:
	@if [ ! -f .env ]; then \
		echo ""; \
		echo "$(ROJO)✗ No existe el archivo de configuración (.env)$(RESET)"; \
		echo "  Ejecuta primero: $(NEGRITA)make configurar$(RESET)"; \
		echo ""; \
		exit 1; \
	fi
