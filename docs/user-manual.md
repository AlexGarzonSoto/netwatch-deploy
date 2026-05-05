# Manual de Usuario — NetWatch Dashboard

## Tabla de contenidos

1. [Introducción y tipos de amenazas](#1-introducción-y-tipos-de-amenazas)
2. [Acceso al sistema](#2-acceso-al-sistema)
3. [Roles y permisos](#3-roles-y-permisos)
4. [Dashboard principal](#4-dashboard-principal)
5. [Gestión de eventos de amenaza](#5-gestión-de-eventos-de-amenaza)
6. [Gestión de alertas](#6-gestión-de-alertas)
7. [Escáner de vulnerabilidades](#7-escáner-de-vulnerabilidades)
8. [Remediación de amenazas](#8-remediación-de-amenazas)
9. [Configuración del sistema (Settings)](#9-configuración-del-sistema-settings)
10. [API REST — referencia rápida](#10-api-rest--referencia-rápida)
11. [Flujos de trabajo recomendados](#11-flujos-de-trabajo-recomendados)
12. [Preguntas frecuentes](#12-preguntas-frecuentes)

---

## 1. Introducción y tipos de amenazas

**NetWatch** es un sistema de monitoreo de amenazas en infraestructura de red. Captura tráfico de red en tiempo real (o lo simula en entornos de prueba), analiza los paquetes para detectar patrones maliciosos y genera alertas que los analistas de seguridad pueden gestionar desde este dashboard.

### Tipos de amenazas detectadas

| Tipo | Descripción | Umbral de detección | Severidad típica |
|------|-------------|--------------------|--------------------|
| `PORT_SCAN` | Escaneo de múltiples puertos desde una misma IP en la misma ventana de tiempo | > 20 puertos distintos en 60 s | HIGH |
| `BRUTE_FORCE` | Intentos repetidos de conexión a puertos sensibles (SSH, RDP, BD) | > 10 intentos al mismo puerto | CRITICAL |
| `SYN_FLOOD` | Flood de paquetes SYN sin completar el handshake TCP (ataque DoS) | > 100 paquetes SYN sin ACK | CRITICAL |
| `DNS_TUNNELING` | Paquetes DNS con payload inusualmente grande (posible exfiltración de datos) | UDP puerto 53 con > 512 bytes | HIGH |
| `NORMAL` | Tráfico analizado sin patrones de amenaza detectados | — | INFO / LOW |

### Puertos sensibles monitoreados para BRUTE_FORCE

| Puerto | Servicio |
|--------|---------|
| 22 | SSH |
| 21 | FTP |
| 23 | Telnet |
| 3389 | RDP (Remote Desktop) |
| 5432 | PostgreSQL |
| 3306 | MySQL / MariaDB |
| 27017 | MongoDB |
| 6379 | Redis / Valkey |

---

## 2. Acceso al sistema

### URLs de acceso

| Componente | URL (desarrollo) | URL (producción con TLS) |
|-----------|------------------|-----------------------------|
| Dashboard Web | http://localhost:3000 | https://netwatch.tudominio.com |
| API REST | http://localhost:8080 | https://netwatch.tudominio.com/api |
| Grafana (métricas) | http://localhost:3001 | https://grafana.netwatch.tudominio.com |
| RabbitMQ UI | http://localhost:15672 | Solo via túnel SSH en producción |

### Iniciar sesión

1. Navegar a la URL del dashboard
2. Ingresar email y contraseña en el formulario de login
3. Al autenticarse, el sistema emite:
   - **Access token:** válido 30 minutos (se usa en cada petición)
   - **Refresh token:** válido 7 días (se usa para renovar el access token automáticamente)
4. Los tokens se guardan en `localStorage` del navegador
5. El access token se renueva **automáticamente** cuando expira — el usuario no necesita volver a iniciar sesión durante 7 días de uso activo

### Credenciales iniciales

| Email | Contraseña | Rol |
|-------|-----------|-----|
| admin@netwatch.local | NetWatch2024! | ADMIN |
| analista@netwatch.local | NetWatch2024! | ANALYST |

> **Seguridad:** Cambiar estas contraseñas antes de cualquier despliegue en producción. El administrador puede actualizar contraseñas directamente en la base de datos PostgreSQL.

### Cerrar sesión

Hacer clic en **"Salir"** en la barra de navegación superior. Los tokens locales se eliminan del navegador.

---

## 3. Roles y permisos

### Tabla de permisos por funcionalidad

| Funcionalidad | VIEWER | ANALYST | ADMIN |
|--------------|--------|---------|-------|
| Ver dashboard | ✓ | ✓ | ✓ |
| Ver eventos de amenaza | ✓ | ✓ | ✓ |
| Ver alertas | ✓ | ✓ | ✓ |
| Resolver eventos | — | ✓ | ✓ |
| Reconocer (acknowledge) alertas | — | ✓ | ✓ |
| Resolver alertas | — | ✓ | ✓ |
| Marcar como falso positivo | — | ✓ | ✓ |
| Usar el escáner de vulnerabilidades | — | ✓ | ✓ |
| Ver resultados de remediación | ✓ | ✓ | ✓ |
| Configurar interfaz de captura | — | — | ✓ |
| Gestionar usuarios | — | — | ✓ |

### Descripción de roles

**VIEWER (Solo lectura)**
Puede visualizar todos los eventos, alertas y métricas pero no puede modificar su estado. Ideal para directivos, auditores externos o cualquier persona que necesite visibilidad sin capacidad de acción.

**ANALYST (Analista de seguridad)**
Puede gestionar el ciclo de vida completo de eventos y alertas: resolver, reconocer, marcar como falso positivo. También puede usar el escáner de vulnerabilidades. Es el rol recomendado para el equipo SOC.

**ADMIN (Administrador)**
Acceso total incluyendo la configuración del sistema (interfaz de captura de red, gestión de usuarios). Solo debe asignarse a personal técnico de confianza.

---

## 4. Dashboard principal

El dashboard se actualiza automáticamente cada **30 segundos** haciendo polling al endpoint `/api/v1/events/stats/summary`.

### Panel de estadísticas (parte superior)

Muestra 4 tarjetas con contadores en tiempo real:

| Tarjeta | Descripción | Se actualiza |
|---------|-------------|-------------|
| **Total eventos** | Número total de amenazas detectadas (históricas) | Cada 30 s |
| **Sin resolver** | Eventos que aún no han sido atendidos | Cada 30 s |
| **Críticos** | Eventos con severidad CRITICAL activos | Cada 30 s |
| **Altos** | Eventos con severidad HIGH activos | Cada 30 s |

Los contadores incluyen únicamente los eventos de la **última hora** para reflejar el estado actual de seguridad.

### Gráfico de amenazas (sección central)

Gráfico de barras que muestra la distribución de amenazas detectadas por tipo (`PORT_SCAN`, `BRUTE_FORCE`, `SYN_FLOOD`, `DNS_TUNNELING`). Permite identificar de un vistazo qué tipo de ataque es más frecuente en el período actual.

### Tabla de eventos recientes (parte inferior)

Lista los últimos 10 eventos detectados con:
- **Timestamp** de detección
- **IP de origen** del ataque
- **Tipo de amenaza** con etiqueta de color
- **Severidad** con código de color (rojo=CRITICAL, naranja=HIGH, amarillo=MEDIUM)
- **Estado** (resuelto / pendiente)
- **Botón de acción rápida** para resolver directamente desde el dashboard

### Indicadores de estado del sistema

El dashboard también muestra el estado general de los microservicios. Si algún servicio está caído (según Prometheus), aparece un indicador de advertencia.

---

## 5. Gestión de eventos de amenaza

### Navegar a la sección de Eventos

Hacer clic en **"Eventos"** en la barra de navegación lateral izquierda.

### Tabla de eventos

La tabla muestra todos los eventos con paginación (50 por página por defecto). Las columnas son:

| Columna | Descripción |
|---------|-------------|
| Timestamp | Fecha y hora de detección (ordenado del más reciente al más antiguo) |
| IP origen | Dirección IP del host que generó la amenaza |
| IP destino | Dirección IP del objetivo del ataque |
| Protocolo | TCP, UDP u otro |
| Tipo | PORT_SCAN, BRUTE_FORCE, SYN_FLOOD, DNS_TUNNELING |
| Severidad | CRITICAL, HIGH, MEDIUM, LOW, INFO (con color) |
| País | País de origen (enriquecido por OSINT) |
| Estado | Resuelto / Pendiente |
| Acciones | Botón "Resolver" (solo ANALYST/ADMIN) |

### Filtrar eventos

Se pueden aplicar filtros combinados:

| Filtro | Valores posibles |
|--------|-----------------|
| **Severidad** | INFO, LOW, MEDIUM, HIGH, CRITICAL |
| **Tipo de amenaza** | PORT_SCAN, BRUTE_FORCE, SYN_FLOOD, DNS_TUNNELING, NORMAL |
| **Estado** | Todos, Solo pendientes, Solo resueltos |
| **Página** | Navegación por páginas de 50 eventos |

### Ver el detalle completo de un evento

Hacer clic en cualquier fila de la tabla para ver el panel de detalle:

**Datos de red:**
- IPs de origen y destino, puertos, protocolo, flags TCP
- Longitud del paquete y TTL
- Descripción de la amenaza detectada

**Datos OSINT (enriquecidos por worker-osint):**
- País y ciudad de origen
- Proveedor de internet (ASN / ISP)
- Coordenadas geográficas aproximadas
- **Puntuación de abuso (0-100):** indica qué tan conocida es esta IP como fuente de amenazas en bases de datos públicas. 0 = no reportada, 100 = altamente maliciosa.

### Resolver un evento

Un evento "resuelto" indica que el analista lo investigó y tomó las acciones pertinentes.

1. Localizar el evento en la tabla
2. Hacer clic en **"Resolver"** (requiere rol ANALYST o ADMIN)
3. El evento queda marcado como resuelto: desaparece de los contadores de "sin resolver" en el dashboard

> Los eventos resueltos NO se eliminan — permanecen en la base de datos para auditoría. Siempre se pueden consultar con el filtro "Resueltos".

---

## 6. Gestión de alertas

Las alertas se generan **automáticamente** para eventos con severidad **HIGH** y **CRITICAL**. Cada alerta está vinculada a un evento de amenaza específico.

### Navegar a la sección de Alertas

Hacer clic en **"Alertas"** en la barra de navegación.

### Ciclo de vida de una alerta

```
OPEN (nueva, sin atender)
  │
  ├── → ACKNOWLEDGED (analista tomó nota, está investigando)
  │         │
  │         └── → RESOLVED (incidente investigado y cerrado)
  │
  └── → FALSE_POSITIVE (la detección fue incorrecta, se descarta)
```

### Estados de las alertas

| Estado | Descripción | Color en UI |
|--------|-------------|-------------|
| **OPEN** | Alerta nueva, sin atender | Rojo |
| **ACKNOWLEDGED** | Un analista asignó la alerta y está investigando | Amarillo |
| **RESOLVED** | El incidente fue investigado y mitigado | Verde |
| **FALSE_POSITIVE** | La alerta fue descartada como falso positivo | Gris |

### Acciones sobre alertas

**Reconocer (Acknowledge):** Indica que el analista tomó nota del incidente y lo está investigando. Mueve el estado de OPEN a ACKNOWLEDGED.

**Resolver:** Indica que el incidente fue investigado y se tomaron las acciones correctivas. Mueve el estado a RESOLVED.

**Falso positivo:** Indica que la detección fue incorrecta (tráfico legítimo identificado como amenaza). Mueve el estado a FALSE_POSITIVE. Esta información puede usarse para ajustar los umbrales del motor de detección.

### Flujo de trabajo estándar con alertas

1. **Revisar alertas OPEN:** Navegar a Alertas → filtrar por estado "OPEN"
2. **Reconocer el incidente:** Hacer clic en "Reconocer" → estado cambia a ACKNOWLEDGED
3. **Investigar:** Hacer clic en la alerta para ver el evento asociado completo (IP, puerto, país, abuseScore, descripción)
4. **Actuar según el tipo de amenaza** (ver sección de Flujos de trabajo recomendados)
5. **Cerrar:** Marcar como "Resolver" (incidente confirmado y mitigado) o "Falso positivo"

---

## 7. Escáner de vulnerabilidades

El escáner permite analizar hosts de la red en busca de puertos abiertos y vulnerabilidades conocidas (CVEs) en los servicios detectados.

### Navegar a la sección Scanner

Hacer clic en **"Scanner"** en la barra de navegación (requiere rol ANALYST o ADMIN).

### Lanzar un escaneo

1. Ingresar la IP o rango CIDR del objetivo (ej: `192.168.1.1` o `192.168.1.0/24`)
2. Hacer clic en **"Escanear"**
3. El escáner ejecuta Nmap en el backend (`worker-scanner`) para detectar puertos y servicios
4. Los resultados se complementan con consultas a la **NVD (National Vulnerability Database)** del NIST para detectar CVEs conocidos en los servicios encontrados

### Resultado del escaneo

Por cada host escaneado se muestra:
- **Puertos abiertos** con el servicio identificado y versión (cuando Nmap puede detectarla)
- **CVEs encontrados** por servicio, con CVSS score y descripción breve
- **Severidad global del host:** basada en el CVE de mayor CVSS detectado

### Modo dry-run (sin ejecutar Nmap real)

Si `SCANNER_DRY_RUN=true` en el `.env`, el escáner simula resultados sin ejecutar Nmap. Útil para pruebas en entornos donde Nmap no está disponible o no está permitido.

> **Consideraciones legales:** Solo escanear redes y hosts para los que se tiene autorización explícita. El escaneo de redes sin autorización puede ser ilegal en muchas jurisdicciones. Usar únicamente en redes propias o con permiso documentado.

---

## 8. Remediación de amenazas

La sección de Remediación proporciona guías de acción para los tipos de amenazas detectadas por NetWatch.

### Navegar a Remediación

Hacer clic en **"Remediación"** en la barra de navegación.

### Guías disponibles

Para cada tipo de amenaza detectada, se muestran:

**PORT_SCAN:**
- Verificar si la IP de origen es un escáner legítimo (herramienta de inventario interna)
- Si es IP externa: considerar bloquear en firewall si el abuseScore es alto
- Revisar qué puertos fueron escaneados para evaluar el objetivo del reconocimiento

**BRUTE_FORCE:**
- Bloquear la IP atacante en el firewall (UFW o iptables)
- Verificar si hubo acceso exitoso revisando los logs del servicio objetivo
- Si hubo acceso: cambiar contraseñas inmediatamente y revisar permisos otorgados
- Considerar autenticación de dos factores para el servicio afectado

**SYN_FLOOD:**
- Activar limitación de rate (iptables o a nivel de proveedor cloud)
- Si el ataque es sostenido: contactar al ISP/proveedor para filtrado upstream
- Verificar que los servicios críticos mantienen disponibilidad

**DNS_TUNNELING:**
- Identificar el proceso/aplicación que genera las consultas DNS inusuales
- Verificar logs de DNS del servidor
- Posible indicador de malware activo usando DNS para comunicaciones C2

---

## 9. Configuración del sistema (Settings)

La sección de Configuración permite ajustar parámetros operacionales del sistema. **Solo accesible para rol ADMIN.**

### Navegar a Configuración

Hacer clic en **"Settings"** en la barra de navegación (solo visible para ADMIN).

### Interfaz de captura de red

Muestra las **interfaces de red disponibles** en el servidor donde corre NetWatch. Esta información se obtiene directamente del sistema operativo host a través del worker-capture.

**Cómo funciona:**
El contenedor del worker-capture tiene acceso de lectura al directorio `/sys/class/net` del host via un volumen Docker. Esto permite listar las interfaces reales del servidor (no las del contenedor).

**Interfaz activa:** Muestra la interfaz actualmente configurada para capturar tráfico.

**Cambiar interfaz:**
1. Ver la lista de interfaces disponibles (ej: eth0, wlan0, lo)
2. Seleccionar la interfaz deseada
3. Confirmar el cambio — el worker-capture se reconfigura para capturar en la nueva interfaz
4. Verificar el estado de captura tras el cambio

> **Nota sobre interfaces disponibles:** En un servidor con conexión WiFi, aparecerá `wlan0` además de `eth0` y `lo`. En un servidor en la nube, típicamente aparecerá `eth0` o `ens3`. Las interfaces de Docker (`docker0`, `veth*`) se filtran automáticamente.

### Modo de captura actual

El panel de estado muestra si el worker está en:

| Modo | Descripción | Cuándo ocurre |
|------|-------------|---------------|
| **Captura real** | Capturando tráfico de la interfaz configurada | Interfaz existe y tiene tráfico + permisos NET_RAW disponibles |
| **Simulación** | Generando tráfico ficticio para demo | Pcap4J no puede acceder a la interfaz (entorno virtual, sin driver, etc.) |
| **Detenido** | CAPTURE_ENABLED=false en .env | Configurado explícitamente para no capturar |

### Alertas de sistema

El panel de Configuración también muestra alertas activas de Prometheus relacionadas con el sistema:
- Servicios caídos
- Memoria JVM alta
- Colas de RabbitMQ acumulando mensajes

---

## 10. API REST — referencia rápida

La API está disponible en `http://localhost:8080`. Todos los endpoints (excepto autenticación) requieren el header `Authorization: Bearer <accessToken>`.

### Autenticación

```bash
# Login — obtener tokens
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"analista@netwatch.local","password":"NetWatch2024!"}'

# Respuesta:
# {
#   "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
#   "refreshToken": "eyJhbGciOiJIUzI1NiJ9...",
#   "tokenType": "Bearer",
#   "expiresIn": 1800,
#   "role": "ANALYST"
# }

# Guardar el token para usar en las siguientes peticiones
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"analista@netwatch.local","password":"NetWatch2024!"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

# Renovar access token (antes de que expire)
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "X-Refresh-Token: <refreshToken>"

# Logout
curl -X POST http://localhost:8080/api/v1/auth/logout \
  -H "Authorization: Bearer $TOKEN"
```

### Endpoints de eventos

```bash
# Listar eventos (paginado, ordenado por fecha descendente)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events?page=0&size=50&sort=timestamp,desc"

# Filtrar por severidad y tipo
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events?severity=CRITICAL&threatType=BRUTE_FORCE"

# Detalle de un evento específico
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events/{uuid}"

# Resolver un evento
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events/{uuid}/resolve"

# Resumen estadístico (para el dashboard)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events/stats/summary"
```

### Endpoints de alertas

```bash
# Listar alertas por estado (OPEN, ACKNOWLEDGED, RESOLVED, FALSE_POSITIVE)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/alerts?status=OPEN&page=0&size=20"

# Reconocer una alerta
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/alerts/{uuid}/acknowledge"

# Resolver una alerta
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/alerts/{uuid}/resolve"

# Marcar como falso positivo
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/alerts/{uuid}/false-positive"
```

### Exportar eventos

```bash
# Exportar los últimos 500 eventos a JSON
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events?size=500&sort=timestamp,desc" \
  | python3 -m json.tool > eventos-$(date +%Y%m%d).json

# Exportar solo eventos CRITICAL sin resolver
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/events?severity=CRITICAL&resolved=false&size=1000" \
  | python3 -m json.tool > criticos-pendientes.json
```

---

## 11. Flujos de trabajo recomendados

### Turno de guardia — revisión matutina (15 minutos)

1. Abrir el **Dashboard** y revisar los contadores de la última hora
2. Si hay eventos **CRITICAL** nuevos → ir a **Alertas** → filtrar OPEN
3. **Reconocer** (ACKNOWLEDGED) todas las alertas que se van a investigar en el turno
4. Para cada alerta CRITICAL:
   a. Ver el evento asociado → revisar IP, tipo, puertos, país y `abuseScore`
   b. Si `abuseScore > 70` → posible IP maliciosa conocida → considerar bloqueo inmediato en firewall
   c. Investigar si hubo acceso exitoso revisando logs del servicio objetivo
5. Actualizar el estado de cada alerta investigada (RESOLVED o FALSE_POSITIVE)
6. Documentar acciones en el sistema de tickets corporativo

### Investigar un posible ataque de fuerza bruta

1. En **Eventos** → filtrar por `Tipo: BRUTE_FORCE`
2. Identificar la IP de origen y el puerto destino (¿SSH? ¿RDP? ¿BD?)
3. Ver el detalle del evento → revisar `abuseScore` y país de origen
4. Si `abuseScore > 50` o IP externa atacando SSH/RDP → alta probabilidad de ataque real
5. Acción inmediata en el servidor:
   ```bash
   sudo ufw deny from <IP_ATACANTE>
   ```
6. Verificar si hubo login exitoso desde esa IP en el período de ataque
7. Resolver el evento en NetWatch y documentar la acción

### Investigar un posible escaneo de puertos

1. En **Eventos** → filtrar por `Tipo: PORT_SCAN`
2. Revisar la IP de origen:
   - **IP interna (10.x.x.x, 192.168.x.x):** puede ser una herramienta de inventario autorizada. Verificar con el equipo de infraestructura antes de bloquear.
   - **IP externa con abuseScore > 30:** posible reconocimiento previo a ataque
3. Revisar qué puertos fueron escaneados — si incluye puertos de bases de datos o servicios críticos, aumentar la prioridad de investigación
4. Si se confirma como amenaza: bloquear la IP y crear ticket de seguridad

### Gestionar una falsa alarma (False Positive)

Algunas herramientas legítimas de administración de red pueden generar falsos positivos:
- Escáneres de inventario de red internos (Nmap autorizado, Nessus, OpenVAS)
- Balanceadores de carga con healthchecks frecuentes
- Herramientas de monitoreo que verifican múltiples puertos

Para registrar un falso positivo:
1. En **Alertas** → seleccionar la alerta
2. Hacer clic en **"Falso positivo"**
3. El equipo técnico puede ajustar los umbrales del motor de detección si los falsos positivos son frecuentes

---

## 12. Preguntas frecuentes

**¿Por qué no veo eventos nuevos en el dashboard?**

El dashboard se actualiza cada 30 segundos. Si no hay eventos, puede ser que:
- El worker de captura está en modo simulación pero con tráfico simulado pausado
- El worker está detenido o en error

```bash
docker compose logs netwatch-worker-capture | tail -20
```

**¿Por qué el dashboard dice "modo simulación"?**

En entornos de desarrollo, Pcap4J puede no tener acceso a la interfaz de red real. El sistema entra automáticamente en modo simulación y genera tráfico ficticio. Todos los tipos de amenazas se generan igualmente para demostrar la funcionalidad. Ver la sección de Configuración (Settings) para cambiar de modo.

**¿Qué significa un `abuseScore` de 0?**

La IP no está reportada en bases de datos de amenazas conocidas al momento del último enriquecimiento OSINT. Un score de 0 **no garantiza** que la IP sea segura — solo que no tiene historial previo conocido. Analizar el contexto (tipo de ataque, país, puerto objetivo) para evaluar el riesgo.

**¿Puedo cambiar la interfaz de captura desde el dashboard?**

Sí, desde **Settings** (solo ADMIN). Seleccionar la interfaz deseada de la lista de interfaces disponibles. El cambio se aplica al reiniciar el worker-capture.

**¿Con qué frecuencia se actualiza el dashboard?**

El dashboard realiza polling automático cada **30 segundos** al endpoint `/api/v1/events/stats/summary`. La tabla de eventos recientes también se actualiza en cada ciclo de polling.

**¿Cómo veo el historial completo de eventos (más de los últimos 50)?**

En la sección **Eventos**, usar la paginación para navegar por páginas de 50 eventos, ordenados del más reciente al más antiguo. También se puede exportar via API REST.

**¿Por qué la IP de un evento muestra país "Unknown"?**

Puede ocurrir si:
- El worker-osint no pudo contactar ip-api.com (problema de red)
- La IP es privada/interna (10.x.x.x, 192.168.x.x) — las IPs privadas no tienen geolocalización
- La respuesta de ip-api.com estaba vacía para esa IP específica

Las IPs internas son normales si la amenaza proviene de dentro de la red corporativa.

**¿Por qué hay alertas con contadores en 0 para ACKNOWLEDGED/RESOLVED?**

Es comportamiento normal al inicio del sistema. Todas las alertas se crean como OPEN. Los contadores de otros estados aumentan cuando los analistas cambian el estado mediante los botones de la interfaz.

**¿Cómo veo las métricas históricas del sistema?**

Acceder a **Grafana** en http://localhost:3001 con las credenciales configuradas en `GRAFANA_PASSWORD`. Los dashboards muestran métricas de los últimos 7 días por defecto y se puede ajustar el rango de tiempo.

**El token de sesión expiró pero no fui redirigido al login. ¿Es un bug?**

No. El sistema tiene **renovación automática de tokens**. Cuando el access token expira (30 min), el frontend automáticamente solicita uno nuevo usando el refresh token (válido 7 días), sin interrumpir la sesión del usuario. Solo se mostrará el login si el refresh token también ha expirado o si el usuario cerró sesión explícitamente.
