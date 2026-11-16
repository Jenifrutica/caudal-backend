# Arranque local de CAUDAL con un comando. Guía: docs/Arranque-local.md
# Requiere los cuatro repositorios como carpetas hermanas y Docker con Compose.

COMPOSE ?= docker compose
FULL    := $(COMPOSE) --profile full

.DEFAULT_GOAL := help
.PHONY: help env up up-core down ps logs smoke smoke-core reset-db

help: ## Lista los comandos disponibles
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-11s %s\n", $$1, $$2}'

env: ## Crea .env desde .env.example con secretos aleatorios (no lo sobrescribe)
	@scripts/dev-env.sh

up: env ## Construye y levanta db + api + ia + web y espera a que estén sanos
	$(FULL) up -d --build --wait --wait-timeout 600
	@echo "PWA http://localhost:8081  API http://localhost:8080/swagger-ui.html  IA http://localhost:8000/docs"

up-core: env ## Solo db + api (arranque rápido, sin la imagen de la IA)
	$(COMPOSE) --profile core up -d --build --wait --wait-timeout 300

down: ## Detiene los contenedores (conserva los datos)
	$(COMPOSE) --profile full --profile core --profile sim down

ps: ## Estado de los contenedores
	$(COMPOSE) --profile full --profile core --profile sim ps

logs: ## Sigue los logs de todos los servicios
	$(COMPOSE) --profile full --profile core --profile sim logs -f --tail=100

smoke: ## Verifica API, IA y PWA (falla si algo no responde)
	@scripts/smoke.sh full

smoke-core: ## Verifica solo la API
	@scripts/smoke.sh core

reset-db: ## Borra el volumen de PostgreSQL y todos los contenedores (pierde los datos locales)
	$(COMPOSE) --profile full --profile core --profile sim down -v
