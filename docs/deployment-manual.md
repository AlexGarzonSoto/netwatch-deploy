# 🚀 Manual de Despliegue Tecnico — NetWatch

##  📚 Tabla de contenidos

1. [Requisitos de infraestructura](#1-requisitos-de-infraestructura)
2. [Despliegue en desarrollo con Docker Compose](#2-despliegue-en-desarrollo-con-docker-compose)
3. [Despliegue en producción — TLS con Caddy](#3-despliegue-en-producción--tls-con-caddy)
4. [Pasar de simulación a captura real de red](#4-pasar-de-simulación-a-captura-real-de-red)
5. [Despliegue con IaC — OpenTofu + Ansible](#5-despliegue-con-iac--opentofu--ansible)
6. [Monitoreo y observabilidad](#6-monitoreo-y-observabilidad)
7. [Gestión de imágenes Docker](#7-gestión-de-imágenes-docker)
8. [Backup y recuperación](#8-backup-y-recuperación)
9. [Actualización del sistema](#9-actualización-del-sistema)
10. [Hardening de seguridad en producción](#10-hardening-de-seguridad-en-producción)

---

# 🖥️ 1. Requisitos de Infraestructura

## ⚙️ Recursos del servidor

| Modo | CPU | RAM | Disco |
|------|-----|-----|-------|
| Desarrollo / demo | 2 cores | 4 GB | 20 GB |
| Producción mínima | 4 cores | 8 GB | 100 GB SSD |
| Producción recomendada | 8 cores | 16 GB | 500 GB SSD |

## 🐧 Sistema Operativo recomendado

- **Ubuntu 22.04 LTS** o Debian 12 (Bookworm)
- Kernel 5.15+ para soporte completo de contenedores
- Para captura real de tráfico: 2 interfaces de red (1 gestión + 1 captura)

## 🔐 Permisos necesarios

El worker de captura necesita capacidades elevadas para acceder al nivel de paquetes:
- `CAP_NET_ADMIN` — abrir interfaces en modo promiscuo
- `CAP_NET_RAW` — capturar tráfico a nivel de frame Ethernet
- Montaje de `/sys/class/net` del host (modo lectura) para listar interfaces

Estos permisos están configurados en `docker-compose.yml` y son obligatorios incluso en modo simulación para que el contenedor arranque correctamente.

## 🧰 Software requerido

```bash
# Instalar Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Verificar instalación
docker version          # 26.x
docker compose version  # v2.x

# Instalar openssl para generar claves
sudo apt install openssl git -y
```

---

## 🐳 2. Despliegue en desarrollo con Docker Compose

## 📥  Paso 1 — Obtener el proyecto

```bash
git clone https://github.com/AlexGarzonSoto/MonitoreoRedInfra.git
cd MonitoreoRedInfra
```

## ⚙️ Paso 2 — Configurar variables de entorno

```bash
cp .env.example .env
```

Editar `.env` y rellenar los valores obligatorios:

```bash
# Generar claves JWT (OBLIGATORIO — 64+ caracteres)
JWT_SECRET=$(openssl rand -hex 64)
JWT_REFRESH_SECRET=$(openssl rand -hex 64)

# Contraseñas de servicios
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/')
RABBITMQ_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/')
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/')
GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
```

Pegar los valores en el `.env` con un editor:

```bash
nano .env
# o
vim .env
```

## ▶️ Paso 3 — Levantar los servicios

```bash
# Arrancar usando imágenes de Docker Hub (recomendado)
make iniciar

# Solo si modificaste el código fuente y quieres recompilar
make construir

# Monitorear el arranque
docker compose logs -f
```

El orden de inicio es automático gracias a `depends_on` + healthchecks:

```
1. postgres     → healthcheck: SELECT 1 FROM users (confirma que init.sql terminó)
                  condition: service_healthy — los workers esperan aquí
2. rabbitmq     → healthcheck: rabbitmq-diagnostics ping (start_period: 60s)
                  condition: service_started — los workers arrancan en paralelo
                  Spring AMQP reintenta la conexión automáticamente cada 5s
3. valkey       → healthcheck: valkey-cli ping
                  condition: service_healthy — solo worker-osint depende de él
4. api-gateway  → healthcheck: /actuator/health (start-period: 60s)
5. worker-*     → cada uno arranca tras postgres healthy + rabbitmq started
6. frontend     → espera api-gateway healthy
7. prometheus, grafana, loki, promtail → sin dependencias críticas
```

> El API Gateway tarda 60-90 segundos en estar listo la primera vez porque Spring Boot debe conectar a PostgreSQL, ejecutar la validación del schema TimescaleDB y establecer los canales AMQP con RabbitMQ. Si RabbitMQ aún no está completamente listo, Spring AMQP reintenta la conexión automáticamente sin reiniciar el contenedor.

## 🔍 Paso 4 — Verificar la instalación

```bash
# Estado de todos los contenedores
docker compose ps

# Health del gateway
curl http://localhost:8080/actuator/health | python3 -m json.tool

# Test de autenticación
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@netwatch.local","password":"NetWatch2024!"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")
echo "Token obtenido: ${TOKEN:0:20}..."

# Dashboard web
xdg-open http://localhost:3000
```
    
### Comandos de gestión diaria

```bash
# Ver logs de un servicio
docker compose logs -f api-gateway
docker compose logs -f worker-capture

# Reiniciar un servicio específico
docker compose restart api-gateway

# Detener todo sin borrar datos
docker compose down

# Reinicio limpio (borra volúmenes — ¡cuidado en producción!)
docker compose down -v
docker compose up -d
```

---

## 🔐 3. Despliegue en producción — TLS con Caddy

El archivo `docker-compose.prod.yml` es un **override de producción** que añade sobre el stack base:

- **Caddy 2** como reverse proxy con **TLS automático via Let's Encrypt**
- **Límites de recursos** (CPU y RAM) por cada servicio
- Los puertos directos de `frontend` y `grafana` dejan de exponerse (solo accesibles via Caddy)

## 🌐 Arquitectura de red en producción

```
Internet
    │
    ▼
Caddy :80/:443   ← TLS automático Let's Encrypt
    │
    ├── / y /api/*          → frontend:80 / api-gateway:8080
    ├── /actuator/health    → api-gateway:8080 (público)
    ├── /actuator/*         → 403 Forbidden (protegido)
    └── grafana.DOMINIO     → grafana:3000 (subdominio separado)
```

### Requisitos previos

1. **Dominio con DNS configurado** apuntando al servidor.
   - Registro A: `netwatch.tudominio.com → IP_DEL_SERVIDOR`
   - Registro A: `grafana.netwatch.tudominio.com → IP_DEL_SERVIDOR`

2. **Puertos 80 y 443 abiertos** en el firewall del servidor.

3. Caddy necesita poder contactar los servidores de Let's Encrypt (ACME). Verificar conectividad saliente en el puerto 443.

## ▶️ Configuración del `.env` para producción

```bash
# Agregar estas variables al .env existente:
DOMAIN=netwatch.tudominio.com

# Cambiar a valores de producción reales si no se hizo en el paso anterior
JWT_SECRET=$(openssl rand -hex 64)
JWT_REFRESH_SECRET=$(openssl rand -hex 64)
```

### Abrir puertos en el firewall

```bash
# Ubuntu/Debian con UFW
sudo ufw allow 80/tcp     # HTTP (Caddy redirige automáticamente a HTTPS)
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 443/udp    # HTTP/3 (QUIC — opcional pero recomendado)
sudo ufw allow 22/tcp     # SSH (restringir a IPs conocidas en producción)

# NO abrir al exterior (acceso solo interno/VPN):
# 8080 (API), 5432 (PostgreSQL), 5672/15672 (RabbitMQ)
# 6379 (Valkey), 9090 (Prometheus), 3001 (Grafana), 3100 (Loki)

sudo ufw enable
sudo ufw status
```

### Iniciar en modo producción

```bash
# Levantar con el override de producción
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Monitorear que Caddy obtiene el certificado TLS
docker compose logs -f caddy
# Salida esperada: "certificate obtained successfully" o similar
```

> **Primera vez:** Caddy tarda 30-60 segundos en obtener el certificado. Después se renueva automáticamente cada 60 días.

### Verificar TLS

```bash
# Verificar el certificado
curl -Iv https://netwatch.tudominio.com 2>&1 | grep -E "SSL|HTTP|issuer"

# Ver detalles del certificado
echo | openssl s_client -connect netwatch.tudominio.com:443 2>/dev/null | openssl x509 -noout -dates -issuer
```

### Prueba con HTTPS local (certificado auto-firmado)

Para probar el stack de producción localmente sin dominio real:

```bash
# .env
DOMAIN=localhost

docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
# Caddy genera un certificado local auto-firmado
# Acceder en: https://localhost (ignorar advertencia del navegador)
```

### Límites de recursos configurados

| Servicio | RAM límite | RAM reservada | CPU límite |
|---------|-----------|--------------|------------|
| postgres | 1 GB | 512 MB | 1.0 |
| rabbitmq | 512 MB | 256 MB | 0.5 |
| valkey | 256 MB | 128 MB | 0.25 |
| api-gateway | 512 MB | 256 MB | 1.0 |
| worker-capture | 256 MB | 128 MB | 0.5 |
| worker-analysis | 512 MB | 256 MB | 0.5 |
| worker-alerts | 256 MB | 128 MB | 0.25 |
| worker-osint | 256 MB | 128 MB | 0.25 |
| worker-scanner | 512 MB | 256 MB | 1.0 |
| frontend | 128 MB | 64 MB | 0.25 |
| prometheus | 512 MB | 256 MB | 0.5 |
| grafana | 256 MB | 128 MB | 0.25 |
| loki | 256 MB | 128 MB | 0.25 |
| caddy | 128 MB | 64 MB | 0.25 |

> **Total estimado:** ~4 GB RAM y ~6 CPU cores bajo carga moderada.

### Diferencias entre modo desarrollo y producción

| Característica | Desarrollo | Producción |
|----------------|-----------|-----------|
| Comando | `docker compose up -d` | `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d` |
| TLS | No (HTTP) | Sí (Let's Encrypt automático) |
| Puerto frontend | 3000 directo | Solo via Caddy 443 |
| Puerto Grafana | 3001 directo | Solo via Caddy 443 (subdominio) |
| Límites RAM/CPU | Sin límites | Configurados por servicio |
| Actuator | Expuesto completo | Solo `/health` público, resto bloqueado |
| Logs | Por docker compose | JSON-file con rotación 50MB×3 |

---

## 📡 4. Pasar de simulación a captura real de red

### Entender el modo actual

El `worker-capture` implementa un sistema de fallback en 3 niveles:

```
1. Lee interfaces del HOST via /host/sys/class/net (montaje Docker)
   ↓ (si el directorio no existe o está vacío)
2. Intenta captura real con Pcap4J
   ↓ (si Pcap4J falla — interfaz no existe, sin permisos raw socket)
3. Modo simulación — genera tráfico ficticio automáticamente
```

```bash
# Ver el modo activo en los logs
docker compose logs worker-capture | grep -iE "captura|simul|interfaz|pcap" | tail -10
```

## 🔍  Verificar las interfaces disponibles en el servidor

```bash
# En el servidor host — listar todas las interfaces
ip link show

# Interfaces de red típicas:
# eth0 / ens3 / enp3s0   → Ethernet
# wlan0 / wlp2s0         → WiFi
# lo                     → Loopback (no útil para monitoreo)
# docker0 / veth*        → Interfaces de Docker (excluidas automáticamente)

# Via API del worker-capture
curl http://localhost:8082/capture/interfaces
```

Salida de ejemplo del endpoint:
```json
[
  {"name": "eth0",  "description": "Ethernet/Loopback", "source": "host"},
  {"name": "wlan0", "description": "WiFi",              "source": "host"},
  {"name": "lo",    "description": "Loopback",          "source": "host"}
]
```

### Activar captura real

**1. Identificar la interfaz correcta:**

```bash
# Ver qué interfaz tiene tráfico activo
iftop -i eth0   # (instalar con: apt install iftop)
# o
tcpdump -i eth0 -c 5  # ver primeros 5 paquetes
```

**2. Actualizar el `.env`:**

```bash
CAPTURE_INTERFACE=eth0    # reemplazar con tu interfaz real
CAPTURE_ENABLED=true
```

**3. Reiniciar solo el worker:**

```bash
docker compose up -d --no-deps --force-recreate worker-capture
```

**4. Verificar captura activa:**

```bash
# Logs del worker
docker compose logs -f worker-capture
# Esperado: "Captura iniciada en interfaz eth0"
# Y: "Paquete capturado: 192.168.1.x:PORT → ..."

# Estado via API
curl http://localhost:8082/capture/status
```

### Consideraciones de seguridad para captura real

- El worker tiene acceso a **todo el tráfico de la interfaz**, incluyendo tráfico no cifrado
- Usar en redes internas/de gestión, nunca en interfaces que procesen datos sensibles (producciones bancarias, médicas, etc.)
- El volumen `/sys/class/net` está montado en **modo lectura** (`ro`) — el contenedor no puede modificar la configuración de red del host
- Las reglas de Falco (`monitoring/falco/falco-rules.yml`) detectan si otro proceso intenta hacer capturas no autorizadas

### Volver a simulación

Para entornos de prueba o cuando no hay tráfico de red relevante:

```bash
# Opción 1: cambiar a una interfaz que no existe
CAPTURE_INTERFACE=nonexistent0

# Opción 2: deshabilitar completamente
CAPTURE_ENABLED=false

# Reiniciar
docker compose up -d --no-deps worker-capture
```

---

## ☁️ 5. Despliegue con IaC — OpenTofu + Ansible

### OpenTofu (fork OSS de Terraform)

El directorio `infrastructure/terraform/` contiene la IaC para provisionar el servidor en la nube.

```bash
# Instalar OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash

# Inicializar providers
cd infrastructure/terraform
tofu init

# Ver el plan de cambios antes de aplicar
tofu plan -var-file="production.tfvars"

# Aplicar la infraestructura
tofu apply -var-file="production.tfvars"

# Obtener la IP del servidor aprovisionado
tofu output server_ip
```

> `production.tfvars` contiene las variables sensibles del proveedor cloud (tokens, regiones). Está en `.gitignore` y no se versionea.

### Ansible — configuración del servidor

Después de que OpenTofu crea el servidor, Ansible lo configura:

```bash
# Instalar Ansible
pip install ansible-core

# El playbook site.yml ejecuta estos pasos en orden:
# 1. Actualizar paquetes del SO
# 2. Instalar Docker Engine y Docker Compose
# 3. Crear usuario de servicio (netwatch) sin privilegios
# 4. Copiar el repositorio al servidor
# 5. Crear el archivo .env con las variables de producción
# 6. Ejecutar docker compose up -d (modo producción)
# 7. Configurar UFW (firewall)
# 8. Configurar logrotate para logs de Docker

# Ejecutar el playbook
ansible-playbook \
  -i infrastructure/ansible/inventory.ini \
  infrastructure/ansible/site.yml \
  --ask-become-pass
```

---

## 📈 6. Monitoreo y observabilidad

### Prometheus — métricas

**URL:** http://localhost:9090 (desarrollo) | https://netwatch.tudominio.com/prometheus (producción con autenticación)

Cada microservicio expone métricas en `/actuator/prometheus`. El scrape interval es de 15 segundos.

**Endpoints de métricas por servicio:**

| Servicio | Endpoint de métricas |
|---------|---------------------|
| api-gateway | http://api-gateway:8080/actuator/prometheus |
| worker-analysis | http://worker-analysis:8081/actuator/prometheus |
| worker-capture | http://worker-capture:8082/actuator/prometheus |
| worker-alerts | http://worker-alerts:8083/actuator/prometheus |
| worker-osint | http://worker-osint:8084/actuator/prometheus |
| worker-scanner | http://worker-scanner:8085/actuator/prometheus |
| RabbitMQ | http://rabbitmq:15692/metrics |

**Reglas de alerta configuradas** (`monitoring/prometheus/alert-rules.yml`):

| Alerta | Condición | Severidad |
|--------|-----------|-----------|
| `ServicioNetWatchCaido` | Servicio sin responder 1 minuto | critical |
| `RabbitMQCaido` | Broker sin responder 1 minuto | critical |
| `MemoriaJVMAlta` | Heap JVM > 85% durante 5 minutos | warning |
| `MemoriaJVMCritica` | Heap JVM > 95% durante 2 minutos | critical |
| `TasaErroresHTTPAlta` | Tasa de errores 5xx > 5% durante 3 minutos | warning |
| `LatenciaP99Alta` | Percentil 99 de latencia > 2s durante 5 minutos | warning |
| `ColaMensajesCreciendo` | Cola con > 1000 mensajes pendientes 5 minutos | warning |
| `ColaMensajesCritica` | Cola con > 5000 mensajes pendientes 2 minutos | critical |

Consultar alertas activas:
```bash
curl http://localhost:9090/api/v1/alerts | python3 -m json.tool
```

### Grafana — dashboards

**URL:** http://localhost:3001 (desarrollo) | https://grafana.netwatch.tudominio.com (producción)

**Credenciales:** `admin` / `<GRAFANA_PASSWORD del .env>`

Dashboards disponibles:
- **NetWatch Overview:** Eventos por severidad, alertas activas, throughput de mensajes, estado de servicios
- **JVM Metrics:** Heap, GC, threads, pool de conexiones por microservicio
- **RabbitMQ:** Profundidad de colas, tasa de mensajes publicados/consumidos, consumers activos

### Loki — logs centralizados

Loki + Promtail recolectan automáticamente los logs de **todos los contenedores** Docker. Se consultan desde Grafana → Explore.

**Queries LogQL útiles:**

```logql
# Todos los logs del API Gateway
{job="netwatch-api-gateway"}

# Errores en cualquier servicio
{job=~"netwatch-.*"} |= "ERROR"

# Amenazas detectadas por el worker de análisis
{job="netwatch-worker-analysis"} |= "amenaza detectada"

# Intentos de login fallidos
{job="netwatch-api-gateway"} |= "Credenciales inválidas"

# Alertas generadas
{job="netwatch-worker-alerts"} |= "Alerta"
```

### Falco — seguridad en runtime

Falco detecta comportamiento anómalo en contenedores. Las reglas están en `monitoring/falco/falco-rules.yml`.

Alertas configuradas:
- Captura de red (`tcpdump`, `tshark`, `scapy`) fuera del worker-capture
- Ejecución de `su` o `sudo` dentro de un contenedor NetWatch
- Escritura en `/etc` desde un contenedor NetWatch

---

## 💾 7. Gestión de imágenes Docker

### Build manual de una imagen

```bash
# El contexto de build SIEMPRE debe ser el directorio raíz del proyecto
# (los Dockerfiles copian el pom.xml padre y múltiples módulos)

# Build de un servicio específico
docker build \
  -f netwatch-api-gateway/Dockerfile \
  -t netwatch-api-gateway:1.0.0 \
  .

# Build de todos los servicios
for service in netwatch-api-gateway netwatch-worker-analysis \
               netwatch-worker-capture netwatch-worker-alerts \
               netwatch-worker-osint netwatch-worker-scanner; do
  echo "Building ${service}..."
  docker build -f ${service}/Dockerfile -t ${service}:1.0.0 .
done
```

### Publicar a Docker Hub

El workflow `deploy.yml` se activa automáticamente al crear un tag semver:

```bash
# Crear y subir un tag de release
git tag -a v1.0.0 -m "Release 1.0.0 — primera versión estable"
git push origin v1.0.0

# GitHub Actions ejecuta automáticamente:
# 1. Compila todos los módulos con Maven
# 2. Construye las imágenes Docker
# 3. Publica a Docker Hub con tags: 1.0.0, 1.0, latest
```

**Secrets requeridos en GitHub:**
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN` (desde hub.docker.com → Security → Access Tokens)

---

## 🔐 8. Backup y recuperación

### Backup de PostgreSQL

```bash
# Backup completo en SQL
docker compose exec postgres pg_dump \
  -U netwatch netwatch \
  > backup-$(date +%Y%m%d-%H%M).sql

# Backup comprimido (recomendado para producción)
docker compose exec postgres pg_dump \
  -U netwatch -Fc netwatch \
  > backup-$(date +%Y%m%d-%H%M).dump

# Backup automático diario con cron
echo "0 2 * * * cd /ruta/al/proyecto && docker compose exec -T postgres pg_dump -U netwatch netwatch | gzip > /backups/netwatch-\$(date +\%Y\%m\%d).sql.gz" | sudo crontab -
```

### Restaurar backup

```bash
# Detener servicios que escriben en la BD
docker compose stop api-gateway worker-analysis worker-osint

# Restaurar desde SQL
docker compose exec -i postgres psql \
  -U netwatch netwatch \
  < backup-20240101.sql

# Restaurar desde formato custom
docker compose exec -i postgres pg_restore \
  -U netwatch -d netwatch -c \
  < backup-20240101.dump

# Reiniciar servicios
docker compose start api-gateway worker-analysis worker-osint
```

### Backup de volúmenes Docker

```bash
# Backup del volumen de PostgreSQL (todos los datos)
docker run --rm \
  -v proyectofinal_postgres_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/postgres-vol-$(date +%Y%m%d).tar.gz -C /data .

# Backup de Grafana (dashboards y configuración)
docker run --rm \
  -v proyectofinal_grafana_data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/grafana-vol-$(date +%Y%m%d).tar.gz -C /data .
```

---

## 9. Actualización del sistema

### Actualización de servicios con mínimo downtime

```bash
# 1. Obtener los últimos cambios
git pull origin main

# 2. Reconstruir las imágenes
docker compose build --no-cache

# 3. Reiniciar servicios uno por uno (sin detener el sistema completo)
docker compose up -d --no-deps api-gateway
sleep 30   # esperar a que el gateway esté listo

docker compose up -d --no-deps worker-analysis
docker compose up -d --no-deps worker-alerts
docker compose up -d --no-deps worker-osint
docker compose up -d --no-deps worker-scanner

# worker-capture: requiere permisos especiales, reiniciar con cuidado
docker compose up -d --no-deps worker-capture
```

### Rollback a versión anterior

```bash
# Volver a un commit anterior
git checkout v1.0.0

# Reconstruir y desplegar
docker compose build
docker compose up -d
```

### Actualizar solo una imagen (sin recompilar)

```bash
# Si la imagen ya está en Docker Hub
docker compose pull api-gateway
docker compose up -d --no-deps api-gateway
```

### Migración de base de datos

1. El modo de desarrollo usa `spring.jpa.hibernate.ddl-auto=update` (el esquema se actualiza automáticamente)
2. Para producción, cambiar a `validate` y gestionar migraciones con scripts SQL o Flyway/Liquibase
3. **Siempre hacer backup** antes de aplicar cambios de esquema
4. El archivo `infrastructure/sql/init.sql` solo se ejecuta al crear la BD por primera vez

---

## 10. Hardening de seguridad en producción

### Variables de entorno críticas

```bash
# JWT: siempre únicas, nunca valores de ejemplo
JWT_SECRET=$(openssl rand -hex 64)
JWT_REFRESH_SECRET=$(openssl rand -hex 64)

# Base de datos: contraseña fuerte
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/')

# NUNCA exponer contraseñas de BD o JWT en logs ni en código
```

### Rotación de claves (cada 90 días en producción)

```bash
# 1. Generar nuevas claves
NEW_JWT_SECRET=$(openssl rand -hex 64)
NEW_JWT_REFRESH=$(openssl rand -hex 64)

# 2. Actualizar .env (las claves viejas invalidarán todos los tokens activos)
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=${NEW_JWT_SECRET}/" .env
sed -i "s/^JWT_REFRESH_SECRET=.*/JWT_REFRESH_SECRET=${NEW_JWT_REFRESH}/" .env

# 3. Reiniciar el api-gateway (los usuarios deberán volver a autenticarse)
docker compose up -d --no-deps api-gateway
```

### Pool de conexiones PostgreSQL (HikariCP)

La configuración del pool está optimizada en `application.properties`:

```properties
spring.datasource.hikari.maximum-pool-size=20       # máximo 20 conexiones
spring.datasource.hikari.minimum-idle=5             # mínimo 5 conexiones siempre activas
spring.datasource.hikari.idle-timeout=300000        # cerrar conexiones inactivas > 5 min
spring.datasource.hikari.connection-timeout=20000   # timeout para obtener conexión: 20s
spring.datasource.hikari.max-lifetime=1200000       # máxima vida de una conexión: 20 min
```

Para monitorear el estado del pool:
```bash
curl http://localhost:8080/actuator/metrics/hikaricp.connections.active
curl http://localhost:8080/actuator/metrics/hikaricp.connections.pending
```

### Rotación de logs

Todos los servicios tienen rotación de logs configurada en `docker-compose.yml` via el anchor YAML:

```yaml
x-logging: &default-logging
  logging:
    driver: "json-file"
    options:
      max-size: "50m"    # máximo 50 MB por archivo
      max-file: "3"      # mantener máximo 3 archivos
```

Esto limita el espacio en disco a 50 MB × 3 = **150 MB máximo por servicio**.

### Acceso a la Management UI de RabbitMQ

En producción, la UI de RabbitMQ (puerto 15672) **no debe estar expuesta en Internet**:

```bash
# Solo acceder via túnel SSH en producción
ssh -L 15672:localhost:15672 usuario@servidor
# Luego abrir: http://localhost:15672
```

### Checklist de seguridad antes de go-live

- [ ] `.env` tiene claves JWT generadas con `openssl rand -hex 64`
- [ ] Todas las contraseñas son únicas y no son los valores de ejemplo
- [ ] Puertos 5432, 5672, 6379, 15672 no están expuestos al exterior (solo 80/443)
- [ ] TLS está activo y el certificado es válido (`curl -Iv https://tudominio`)
- [ ] Grafana tiene contraseña cambiada desde el valor por defecto
- [ ] Los usuarios de prueba (`admin@netwatch.local`) tienen contraseñas actualizadas
- [ ] Falco está corriendo y generando alertas: `docker compose logs falco`
- [ ] Los backups automáticos de PostgreSQL están configurados con cron
- [ ] La rotación de logs limita el uso de disco (verificar con `docker system df`)
