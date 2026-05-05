# NetWatch — Sistema de Monitoreo y Análisis de Amenazas en Red

NetWatch es un sistema de detección de amenazas en tiempo real construido con arquitectura de microservicios. Captura tráfico de red, analiza patrones maliciosos mediante un motor de reglas, enriquece los eventos con inteligencia OSINT geográfica y genera alertas que los analistas de seguridad pueden gestionar desde un dashboard web. Es el trabajo final de la Especialización en Ciberseguridad con énfasis en DevSecOps.

[![CI — NetWatch Security Pipeline](https://github.com/AlexGarzonSoto/MonitoreoRedInfra/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexGarzonSoto/MonitoreoRedInfra/actions/workflows/ci.yml)

---

## Contenido

1. [Requisitos técnicos](#1-requisitos-técnicos)
2. [Inicio rápido (desarrollo)](#2-inicio-rápido-desarrollo)
3. [Modo simulación vs captura real](#3-modo-simulación-vs-captura-real)
4. [Despliegue en producción](#4-despliegue-en-producción)
5. [Arquitectura](#5-arquitectura)
6. [Servicios y puertos](#6-servicios-y-puertos)
7. [Credenciales de prueba](#7-credenciales-de-prueba)
8. [Pipeline DevSecOps](#8-pipeline-devsecops)
9. [Stack tecnológico](#9-stack-tecnológico)
10. [Documentación](#10-documentación)
11. [Licencia](#11-licencia)

---

## 1. Requisitos técnicos

### Para ejecutar (usuario final / operaciones)

| Herramienta | Versión mínima | Propósito |
|-------------|---------------|-----------|
| Docker Engine | 26.x | Contenedores |
| Docker Compose v2 | 2.x | Orquestación |
| Git | 2.x | Clonar el repositorio |
| openssl | cualquier | Generar claves JWT |

### Para desarrollar (opcional)

| Herramienta | Versión mínima | Propósito |
|-------------|---------------|-----------|
| Java OpenJDK | 21 LTS | Compilación local |
| Maven | 3.9+ | Build y tests |
| Node.js | 20 LTS | Frontend |

> **Nota:** En producción solo se necesitan Docker y Docker Compose. Las imágenes pre-compiladas se obtienen de Docker Hub o se construyen con `docker compose build`.

### Recursos del servidor

| Modo | CPU | RAM | Disco |
|------|-----|-----|-------|
| Desarrollo / demo | 2 cores | 4 GB | 20 GB |
| Producción mínima | 4 cores | 8 GB | 100 GB SSD |
| Producción recomendada | 8 cores | 16 GB | 500 GB SSD |

---

## 2. Inicio rápido (desarrollo)

### Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/AlexGarzonSoto/MonitoreoRedInfra.git
cd MonitoreoRedInfra
```

### Paso 2 — Crear el archivo de variables de entorno

```bash
cp .env.example .env
```

Editar `.env` y completar los valores. Los campos mínimos obligatorios son:

```bash
# Claves JWT — generar con openssl (OBLIGATORIO cambiar):
JWT_SECRET=$(openssl rand -hex 64)
JWT_REFRESH_SECRET=$(openssl rand -hex 64)

# Contraseñas de servicios (OBLIGATORIO cambiar):
POSTGRES_PASSWORD=tu_password_seguro
RABBITMQ_PASSWORD=tu_password_seguro
REDIS_PASSWORD=tu_password_seguro
GRAFANA_PASSWORD=tu_password_seguro
```

> **Importante:** Nunca usar los valores de ejemplo de `.env.example` en producción. Generar claves únicas con `openssl rand -hex 64`.

### Paso 3 — Levantar los servicios

```bash
# Construir y arrancar todos los servicios
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

## 3. Modo simulación vs captura real

NetWatch tiene dos modos de operación para el worker de captura de paquetes. El modo se controla con la variable `CAPTURE_ENABLED` en el archivo `.env`.

### Modo simulación (por defecto — `CAPTURE_ENABLED=true`, sin interfaz física disponible)

En este modo, el worker genera tráfico de red aleatorio internamente para demostrar todas las funcionalidades del sistema sin necesidad de tráfico real. Es ideal para:

- Entornos de desarrollo donde no hay tráfico de red relevante
- Máquinas virtuales o servidores en la nube
- Demos y pruebas funcionales

El simulador genera automáticamente todos los tipos de amenazas (PORT_SCAN, BRUTE_FORCE, SYN_FLOOD, DNS_TUNNELING) con distintas severidades para poblar el dashboard.

```bash
# .env — modo simulación (comportamiento por defecto)
CAPTURE_INTERFACE=eth0        # interfaz que intentará usar
CAPTURE_ENABLED=true          # el worker arranca y simula si Pcap4J no puede capturar
```

Para verificar que está en modo simulación:
```bash
docker compose logs worker-capture | grep -i "simul"
# Salida esperada: "Pcap4J no disponible, usando simulación"
```

### Modo captura real (producción)

Para capturar tráfico real de red, el sistema necesita:
1. Una interfaz de red disponible en el host
2. Permisos `NET_ADMIN` y `NET_RAW` (ya configurados en `docker-compose.yml`)
3. Montaje de `/sys/class/net` del host al contenedor (ya configurado)

**Pasos para activar captura real:**

1. Identificar la interfaz de red correcta:
```bash
# Ver interfaces disponibles en el host
ip link show
# o consultar la API del worker
curl http://localhost:8082/capture/interfaces
```

2. Actualizar `.env` con la interfaz correcta:
```bash
# .env — modo captura real
CAPTURE_INTERFACE=wlan0     # cambiar según tu interfaz (eth0, ens3, wlan0, etc.)
CAPTURE_ENABLED=true
```

3. Reiniciar el worker de captura:
```bash
docker compose up -d --no-deps --force-recreate worker-capture
```

4. Verificar que captura tráfico real:
```bash
docker compose logs -f worker-capture
# Salida esperada: "Captura iniciada en interfaz wlan0"
```

> **Nota de seguridad:** El worker de captura tiene capacidades elevadas (`NET_ADMIN`, `NET_RAW`). Está monitoreado por Falco. No ejecutar en redes de producción sin haber revisado `monitoring/falco/falco-rules.yml`.

### Desactivar la captura completamente

```bash
# .env
CAPTURE_ENABLED=false
# Reiniciar
docker compose up -d --no-deps worker-capture
```

---

## 4. Despliegue en producción

NetWatch incluye un archivo de override de producción (`docker-compose.prod.yml`) que añade:
- **Límites de recursos** (CPU y RAM) por cada servicio
- **Caddy** como reverse proxy con **TLS automático via Let's Encrypt**
- Los puertos internos (frontend, Grafana) dejan de estar expuestos directamente

### Configuración previa

1. Asegurarse de tener un dominio apuntando al servidor (DNS configurado).

2. Agregar al `.env`:
```bash
DOMAIN=netwatch.tudominio.com          # dominio principal → accede al dashboard
# Grafana quedará en: grafana.netwatch.tudominio.com
```

3. Abrir los puertos en el firewall:
```bash
sudo ufw allow 80/tcp     # HTTP (redirige a HTTPS automáticamente)
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 443/udp    # HTTP/3 (QUIC)
sudo ufw allow 22/tcp     # SSH (solo desde IPs de gestión)
```

### Levantar en modo producción

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Caddy obtiene el certificado TLS automáticamente en el primer arranque (requiere que el DNS esté propagado).

### Verificar TLS

```bash
curl -I https://netwatch.tudominio.com
# HTTP/2 200 — certificado Let's Encrypt activo
```

### Para desarrollo local con HTTPS (certificado auto-firmado)

```bash
# .env
DOMAIN=localhost

docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
# Caddy genera un certificado local auto-firmado
```

---

## 5. Arquitectura

### Flujo de procesamiento

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RED DE RED (host)                            │
└──────────────────────────────┬──────────────────────────────────────┘
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
             │                                                  │[threats.detected]
             ▼                                                  │ (enriquecido)
    ┌──────────────────┐                                        ▼
    │   PostgreSQL     │◄───────────────────────────── api-gateway
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

## 6. Servicios y puertos

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

## 7. Credenciales de prueba

| Usuario | Contraseña | Rol | Acceso |
|---------|-----------|-----|--------|
| `admin@netwatch.local` | `NetWatch2024!` | ADMIN | Total (incluyendo gestión de usuarios) |
| `analista@netwatch.local` | `NetWatch2024!` | ANALYST | Gestión de eventos y alertas |

> **Seguridad:** Cambiar estas contraseñas antes de cualquier despliegue. Actualizar el hash BCrypt en `infrastructure/sql/init.sql` o directamente en la tabla `users` de PostgreSQL.

Para generar un hash BCrypt compatible (strength 12):
```bash
# Con htpasswd (apache2-utils)
htpasswd -bnBC 12 "" "NuevaContrasena123!" | tr -d ':\n' | sed 's/$2y/$2a/'

# Con Python
python3 -c "import bcrypt; print(bcrypt.hashpw(b'NuevaContrasena123!', bcrypt.gensalt(12)).decode())"
```

---

## 8. Pipeline DevSecOps

El pipeline de GitHub Actions ejecuta **7 etapas de seguridad** en cada push a `main` o `develop`:

```
  ┌─────────────┐
  │secrets-scan │  Gitleaks — historial completo de Git
  └──────┬──────┘
         │
    ┌────┴────┐──────────────┐
    ▼         ▼              ▼
  ┌─────┐  ┌─────┐       ┌──────────┐
  │sast │  │ sca │       │iac-scan  │
  │SpotB│  │OWASP│       │Checkov   │
  │Semg │  │DepCk│       │Dockerfls │
  └──┬──┘  └──┬──┘       └──────────┘
     └────┬───┘
          ▼
  ┌───────────────┐
  │build-and-scan │  Trivy CRITICAL — 6 servicios en paralelo
  └───────┬───────┘
          ▼
  ┌───────────────┐
  │  unit-tests   │  JUnit 5 + JaCoCo ≥ 70%
  └───────┬───────┘
          ▼
  ┌───────────────┐
  │     dast      │  OWASP ZAP Baseline
  └───────────────┘
```

### Herramientas de seguridad por fase

| Fase DevSecOps | Herramienta | Propósito | Falla el build |
|----------------|------------|-----------|---------------|
| **CODE** | Gitleaks | Secretos en código/historial git | Sí |
| **CODE** | SpotBugs + Find Security Bugs | SAST — bytecode Java | No (reporta) |
| **CODE** | Semgrep OSS | SAST semántico OWASP Top 10 | No (reporta) |
| **CODE** | OWASP Dependency-Check | SCA — CVEs en dependencias Maven | No (reporta) |
| **BUILD** | Trivy | CVEs CRITICAL en imágenes Docker | Sí |
| **TEST** | JaCoCo | Cobertura de código ≥ 70% | Sí |
| **TEST** | OWASP ZAP Baseline | DAST — escaneo pasivo de la API | Advertencia |
| **RELEASE** | Checkov | IaC — Dockerfiles y Compose | No (reporta) |

### Secrets requeridos en GitHub

| Secret | Descripción |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Usuario de Docker Hub |
| `DOCKERHUB_TOKEN` | Access Token Docker Hub (no contraseña) |
| `NVD_API_KEY` | API key de nvd.nist.gov (gratuita) |

---

## 9. Stack tecnológico

Todas las herramientas tienen licencia **OSI aprobada**. Redis y Terraform fueron reemplazados por sus forks open source.

| Capa | Tecnología | Versión | Licencia |
|------|-----------|---------|---------|
| Backend | Java OpenJDK + Spring Boot | 21 LTS / 3.2.5 | GPL v2+CE / Apache 2.0 |
| Mensajería | RabbitMQ | 3.12 | Mozilla PL 2.0 |
| Base de datos | PostgreSQL + TimescaleDB | 15 | PostgreSQL License |
| Caché | **Valkey** (fork OSS de Redis) | 7.2 | BSD 3-Clause |
| Captura de red | Pcap4J | 2.0.0-alpha.6 | MIT |
| Autenticación | jjwt (HMAC-SHA256) | 0.12.5 | Apache 2.0 |
| Frontend | Vue.js 3 + Vite + Pinia | 3.x | MIT |
| Servidor web | Nginx | alpine | BSD |
| Proxy / TLS | Caddy 2 | 2-alpine | Apache 2.0 |
| Contenedores | Docker + Compose v2 | 26.x | Apache 2.0 |
| IaC | **OpenTofu** (fork OSS de Terraform) | 1.7 | Mozilla PL 2.0 |
| Config. mgmt | Ansible Core | latest | GPL v3 |
| CI/CD | GitHub Actions | — | Gratis (repos públicos) |
| SAST | SpotBugs + Find Security Bugs | 4.8.3.1 | LGPL |
| SAST semántico | Semgrep OSS | latest | LGPL |
| SCA | OWASP Dependency-Check | 9.x | Apache 2.0 |
| Escaneo imágenes | Trivy | latest | Apache 2.0 |
| DAST | OWASP ZAP | latest | Apache 2.0 |
| Secretos | Gitleaks | 8.18.2 | MIT |
| IaC scan | Checkov | latest | Apache 2.0 |
| Métricas | Prometheus | latest | Apache 2.0 |
| Dashboards | Grafana OSS | latest | AGPL v3 |
| Logs | Loki + Promtail | latest | AGPL v3 |
| Runtime sec. | Falco | latest | Apache 2.0 |

---

## 10. Documentación

| Documento | Descripción |
|-----------|-------------|
| [Manual del Desarrollador](docs/development-manual.md) | Setup del entorno, compilación, variables de entorno, troubleshooting |
| [Manual de Despliegue](docs/deployment-manual.md) | Docker Compose, producción con TLS, IaC, Ansible, backup |
| [Manual de Seguridad](docs/security-manual.md) | STRIDE, pipeline CI/CD, gestión de CVEs, respuesta a incidentes |
| [Manual de Usuario](docs/user-manual.md) | Dashboard, eventos, alertas, scanner, API REST |
| [Diagramas de Arquitectura](https://github.com/AlexGarzonSoto/MonitoreoRedInfra/blob/main/docs/architecture/README.md) | Componentes, despliegue, secuencia JWT y casos de uso (Mermaid, renderiza en GitHub) |
| [Modelo de Amenazas STRIDE](https://github.com/AlexGarzonSoto/MonitoreoRedInfra/blob/main/docs/architecture/threat-model.json) | OWASP Threat Dragon — DFD Nivel 0 y 1 — abrir en threatdragon.com |

---

## 11. Licencia

[Apache License 2.0](LICENSE)

---

*NetWatch — Trabajo Final de Especialización en Ciberseguridad con énfasis en DevSecOps*
