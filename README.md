# NetWatch — Despliegue con Docker Compose

NetWatch es un sistema de detección de amenazas en red en tiempo real, construido con arquitectura de microservicios. Este repositorio contiene únicamente los archivos necesarios para **desplegar NetWatch usando imágenes pre-compiladas de Docker Hub**. No requiere Java, Maven ni Node.js.

> 🔗 Código fuente completo: [AlexGarzonSoto/MonitoreoRedInfra](https://github.com/AlexGarzonSoto/MonitoreoRedInfra)

---

## Contenido

1. [Requisitos](#1-requisitos)
2. [Inicio rápido con Make](#2-inicio-rápido-con-make)
3. [Inicio rápido manual](#3-inicio-rápido-manual)
4. [Modo simulación vs captura real](#4-modo-simulación-vs-captura-real)
5. [Despliegue en producción](#5-despliegue-en-producción)
6. [Arquitectura](#6-arquitectura)
7. [Servicios y puertos](#7-servicios-y-puertos)
8. [Credenciales de prueba](#8-credenciales-de-prueba)
9. [Licencia](#9-licencia)

---

## 1. Requisitos

| Herramienta | Versión mínima | Propósito |
|-------------|---------------|-----------|
| Docker Engine | 26.x | Contenedores |
| Docker Compose v2 | 2.x | Orquestación |
| Git | 2.x | Clonar este repositorio |
| openssl | cualquier | Generar claves JWT (lo hace `make configurar` automáticamente) |

### Recursos del servidor

| Modo | CPU | RAM | Disco |
|------|-----|-----|-------|
| Desarrollo / demo | 2 cores | 4 GB | 20 GB |
| Producción mínima | 4 cores | 8 GB | 100 GB SSD |
| Producción recomendada | 8 cores | 16 GB | 500 GB SSD |

---

## 2. Inicio rápido con Make

La forma más sencilla de levantar NetWatch es usando el `Makefile` incluido:

```bash
# 1. Clonar este repositorio
git clone https://github.com/AlexGarzonSoto/netwatch-deploy.git
cd netwatch-deploy

# 2. Crear la configuración (genera claves JWT automáticamente)
make configurar

# 3. Arrancar NetWatch (descarga imágenes de Docker Hub)
make iniciar
```

### Comandos disponibles

| Comando | Descripción |
|---------|-------------|
| `make configurar` | Primera vez: crea el archivo `.env` con claves generadas |
| `make iniciar` | Arranca NetWatch (descarga imágenes de Docker Hub) |
| `make detener` | Para NetWatch (los datos se conservan) |
| `make estado` | Muestra si todos los servicios funcionan |
| `make logs` | Muestra los logs en tiempo real |
| `make reiniciar` | Para y vuelve a arrancar NetWatch |
| `make abrir` | Abre el dashboard en el navegador |
| `make limpiar` | ⚠️ Borra TODO incluyendo datos guardados |

---

## 3. Inicio rápido manual

Si prefieres no usar Make:

### Paso 1 — Clonar este repositorio

```bash
git clone https://github.com/AlexGarzonSoto/netwatch-deploy.git
cd netwatch-deploy
```

### Paso 2 — Crear el archivo de variables de entorno

```bash
cp .env.example .env
```

Editar `.env` y completar los valores obligatorios:

```bash
# Tu usuario de Docker Hub
DOCKERHUB_USERNAME=alexgarzonsoto

# Claves JWT — generar con openssl (OBLIGATORIO cambiar):
JWT_SECRET=$(openssl rand -hex 64)
JWT_REFRESH_SECRET=$(openssl rand -hex 64)

# Contraseñas de servicios (OBLIGATORIO cambiar):
POSTGRES_PASSWORD=tu_password_seguro
RABBITMQ_PASSWORD=tu_password_seguro
REDIS_PASSWORD=tu_password_seguro
GRAFANA_PASSWORD=tu_password_seguro
```

> ⚠️ **Importante:** Nunca usar los valores de ejemplo en producción. Generar claves únicas con `openssl rand -hex 64`.

### Paso 3 — Levantar los servicios

```bash
# Arrancar todos los servicios (descarga imágenes de Docker Hub)
docker compose up -d

# Seguir los logs mientras arranca
docker compose logs -f api-gateway

# Ver estado de todos los contenedores
docker compose ps
```

El orden de inicio es automático gracias a `depends_on` + healthchecks:
```
postgres → rabbitmq → valkey → api-gateway + workers → frontend + observabilidad
```

El API Gateway tarda ~60-120 segundos en estar listo la primera vez (Spring Boot + TimescaleDB).

### Paso 4 — Verificar la instalación

```bash
# Health del API Gateway
curl http://localhost:8080/actuator/health

# Login de prueba (debe retornar tokens JWT)
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@netwatch.local","password":"NetWatch2024!"}'

# Abrir el dashboard web
xdg-open http://localhost:3000    # Linux
open http://localhost:3000        # macOS
```

---

## 4. Modo simulación vs captura real

NetWatch tiene dos modos de operación para el worker de captura de paquetes, controlado con `CAPTURE_ENABLED` en `.env`.

### Modo simulación (por defecto)

El worker genera tráfico de red aleatorio internamente con todos los tipos de amenazas (PORT_SCAN, BRUTE_FORCE, SYN_FLOOD, DNS_TUNNELING). Ideal para:

- Entornos de desarrollo donde no hay tráfico de red relevante
- Máquinas virtuales o servidores en la nube
- Demos y pruebas funcionales

```bash
# .env — modo simulación
CAPTURE_INTERFACE=eth0
CAPTURE_ENABLED=true
```

Verificar modo activo:
```bash
docker compose logs worker-capture | grep -i "simul"
# Salida esperada: "Pcap4J no disponible, usando simulación"
```

### Modo captura real (producción)

```bash
# 1. Ver interfaces disponibles en el host
ip link show
# o consultar la API del worker
curl http://localhost:8082/capture/interfaces

# 2. Actualizar .env
CAPTURE_INTERFACE=wlan0     # ajustar según tu interfaz
CAPTURE_ENABLED=true

# 3. Reiniciar el worker
docker compose up -d --no-deps --force-recreate worker-capture

# 4. Verificar
docker compose logs -f worker-capture
# Salida esperada: "Captura iniciada en interfaz wlan0"
```

> ⚠️ **Seguridad:** El worker de captura tiene capacidades elevadas (`NET_ADMIN`, `NET_RAW`). Está monitoreado por Falco. No ejecutar en redes de producción sin revisar `monitoring/falco/falco-rules.yml`.

### Desactivar la captura completamente

```bash
# .env
CAPTURE_ENABLED=false
docker compose up -d --no-deps worker-capture
```

---

## 5. Despliegue en producción

NetWatch incluye un archivo de override de producción (`docker-compose.prod.yml`) que añade:
- **Límites de recursos** (CPU y RAM) por cada servicio
- **Caddy** como reverse proxy con **TLS automático via Let's Encrypt**
- Los puertos internos (frontend, Grafana) dejan de estar expuestos directamente

### Configuración previa

1. Tener un dominio apuntando al servidor (DNS configurado).

2. Agregar al `.env`:
```bash
DOMAIN=netwatch.tudominio.com
```

3. Levantar con el override de producción:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## 6. Arquitectura

```
    ┌──────────────────────────────────────────────────────────────┐
    │                      Internet / Red                          │
    └──────────────────────────────┬───────────────────────────────┘
                                   │ CAP_NET_RAW / simulación
                                   ▼
                        ┌──────────────────┐
                        │  worker-capture  │  :8082
                        │  (Pcap4J / sim)  │
                        └────────┬─────────┘
                                 │ [packets.raw]
                                 ▼
                        ┌──────────────────┐
                        │ worker-analysis  │  :8081
                        │ (motor STRIDE)   │
                        └────────┬─────────┘
                PORT_SCAN│BRUTE_FORCE│SYN_FLOOD│DNS_TUNNELING
           ┌─────────────┴──────────────────────────────┐
           │ [threats.detected]    [alerts.notify]       │[osint.enrich]
           ▼                            ▼                ▼
┌──────────────────┐        ┌──────────────────┐  ┌──────────────────┐
│   api-gateway    │        │  worker-alerts   │  │  worker-osint    │
│  :8080 (REST+JWT)│        │  :8083 Email/WH  │  │  :8084 GeoIP     │
└────────┬─────────┘        └──────────────────┘  └────────┬─────────┘
         │                                                  │ (enriquecido)
         ▼                                                  ▼
┌──────────────────┐◄──────────────────────────── api-gateway
│   PostgreSQL     │
│  + TimescaleDB   │
└──────────────────┘

┌──────────────────┐
│  worker-scanner  │  :8085 — Nmap + NVD CVEs (bajo demanda)
└──────────────────┘

┌──────────────────┐    ┌─────────────────────────────────────┐
│    frontend      │    │         Observabilidad               │
│  Vue.js :3000    │    │  Prometheus :9090  Grafana :3001     │
└──────────────────┘    │  Loki :3100   Promtail   Falco       │
                        └─────────────────────────────────────┘
```

### Colas RabbitMQ

| Cola | Routing Key | Productor | Consumidor |
|------|-------------|-----------|------------|
| `netwatch.packets.raw` | `packets.raw` | worker-capture | worker-analysis |
| `netwatch.threats.detected` | `threats.detected` | worker-analysis, worker-osint | api-gateway |
| `netwatch.alerts.notify` | `alerts.notify` | worker-analysis | worker-alerts |
| `netwatch.osint.enrich` | `osint.enrich` | worker-analysis | worker-osint |

---

## 7. Servicios y puertos

### Aplicación

| Servicio | Puerto | Descripción |
|---------|--------|-------------|
| Frontend | http://localhost:3000 | Dashboard Vue.js |
| API Gateway | http://localhost:8080 | REST API + JWT |
| Worker Analysis | http://localhost:8081 | Motor de detección (interno) |
| Worker Capture | http://localhost:8082 | Captura de paquetes |
| Worker Alerts | http://localhost:8083 | Notificaciones Email/Webhook |
| Worker OSINT | http://localhost:8084 | Enriquecimiento GeoIP |
| Worker Scanner | http://localhost:8085 | Nmap + NVD CVEs |

### Infraestructura

| Servicio | Puerto | Descripción |
|---------|--------|-------------|
| PostgreSQL + TimescaleDB | 5432 | Base de datos (no exponer en producción) |
| RabbitMQ AMQP | 5672 | Broker de mensajes (no exponer en producción) |
| RabbitMQ Management UI | http://localhost:15672 | Panel de administración del broker |
| Valkey (compatible Redis) | 6379 | Caché (no exponer en producción) |

### Observabilidad

| Servicio | Puerto | Descripción |
|---------|--------|-------------|
| Prometheus | http://localhost:9090 | Métricas y alertas |
| Grafana | http://localhost:3001 | Dashboards y visualización |
| Loki | http://localhost:3100 | Agregación de logs |

> **En producción:** Con `docker-compose.prod.yml`, los puertos de frontend y Grafana dejan de estar expuestos directamente. Todo el tráfico pasa por Caddy en los puertos 80/443.

---

## 8. Credenciales de prueba

| Usuario | Contraseña | Rol | Acceso |
|---------|-----------|-----|--------|
| `admin@netwatch.local` | `NetWatch2024!` | ADMIN | Total (incluyendo gestión de usuarios) |
| `analista@netwatch.local` | `NetWatch2024!` | ANALYST | Gestión de eventos y alertas |

> ⚠️ **Seguridad:** Cambiar estas contraseñas antes de cualquier despliegue en producción.

---

## 9. Licencia

[Apache License 2.0](LICENSE)

---

*NetWatch — Trabajo Final de Especialización en Ciberseguridad con énfasis en DevSecOps*