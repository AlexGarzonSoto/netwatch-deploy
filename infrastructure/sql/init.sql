-- ─────────────────────────────────────────────────────────────────────────
-- NetWatch — Inicialización de base de datos
-- Se ejecuta automáticamente al arrancar el contenedor de PostgreSQL
-- ─────────────────────────────────────────────────────────────────────────

-- Habilitar extensión TimescaleDB para series temporales
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- ── Tabla: users ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'ANALYST'
                  CHECK (role IN ('ADMIN', 'ANALYST', 'VIEWER')),
    active        BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Tabla: network_events (hypertable TimescaleDB) ────────────────────────
CREATE TABLE IF NOT EXISTS network_events (
    id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    src_ip        VARCHAR(45)  NOT NULL,
    dst_ip        VARCHAR(45),
    src_port      INTEGER,
    dst_port      INTEGER,
    protocol      VARCHAR(10),
    flags         VARCHAR(30),
    packet_length INTEGER,
    ttl           INTEGER,
    threat_type   VARCHAR(30),
    severity      VARCHAR(10),
    description   TEXT,
    country       VARCHAR(100),
    city          VARCHAR(100),
    latitude      DOUBLE PRECISION,
    longitude     DOUBLE PRECISION,
    asn           VARCHAR(100),
    abuse_score   INTEGER DEFAULT 0,
    resolved      BOOLEAN DEFAULT false,
    timestamp     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Convertir en hypertable particionada por día (TimescaleDB)
SELECT create_hypertable(
    'network_events', 'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_events_src_ip
    ON network_events (src_ip, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_severity
    ON network_events (severity, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_threat
    ON network_events (threat_type, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_resolved
    ON network_events (resolved, timestamp DESC);

-- Índices compuestos para queries frecuentes del dashboard
-- Cubre: "eventos no resueltos ordenados por severidad y tiempo"
CREATE INDEX IF NOT EXISTS idx_events_unresolved_severity
    ON network_events (resolved, severity, timestamp DESC)
    WHERE resolved = false;
-- Cubre: "conteo por severidad en ventana de tiempo" (summary endpoint)
CREATE INDEX IF NOT EXISTS idx_events_severity_timestamp
    ON network_events (severity, timestamp DESC);
-- Cubre: "eventos recientes por IP de origen con amenaza"
CREATE INDEX IF NOT EXISTS idx_events_srcip_threat_time
    ON network_events (src_ip, threat_type, timestamp DESC);

-- ── Tabla: alerts ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alerts (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id          UUID,   -- sin FK: network_events es hypertable (TimescaleDB no soporta FK a hypertables)
    title             VARCHAR(255) NOT NULL,
    details           TEXT,
    status            VARCHAR(20)  NOT NULL DEFAULT 'OPEN'
                      CHECK (status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED', 'FALSE_POSITIVE')),
    notification_sent BOOLEAN      DEFAULT false,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_status
    ON alerts (status, created_at DESC);

-- ── Tabla: raw_packets (worker-capture) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS raw_packets (
    id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    src_ip        VARCHAR(45) NOT NULL,
    dst_ip        VARCHAR(45),
    src_port      INTEGER,
    dst_port      INTEGER,
    protocol      VARCHAR(10) NOT NULL,
    flags         VARCHAR(30),
    packet_length INTEGER,
    captured_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT create_hypertable(
    'raw_packets', 'captured_at',
    chunk_time_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- ── Tabla: threat_events (worker-analysis) ────────────────────────────────
CREATE TABLE IF NOT EXISTS threat_events (
    id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    src_ip      VARCHAR(45) NOT NULL,
    dst_ip      VARCHAR(45),
    src_port    INTEGER,
    dst_port    INTEGER,
    protocol    VARCHAR(10),
    flags       VARCHAR(30),
    threat_type VARCHAR(30) NOT NULL,
    severity    VARCHAR(10) NOT NULL,
    description TEXT,
    notified    BOOLEAN     DEFAULT false,
    enriched    BOOLEAN     DEFAULT false,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT create_hypertable(
    'threat_events', 'detected_at',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- ── Tabla: alert_logs (worker-alerts) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS alert_logs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    threat_id     UUID        NOT NULL,
    src_ip        VARCHAR(45) NOT NULL,
    threat_type   VARCHAR(30) NOT NULL,
    severity      VARCHAR(10) NOT NULL,
    channel       VARCHAR(10) NOT NULL CHECK (channel IN ('EMAIL', 'WEBHOOK')),
    success       BOOLEAN     NOT NULL DEFAULT false,
    error_message TEXT,
    sent_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Tabla: osint_records (worker-osint) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS osint_records (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    threat_id   UUID         NOT NULL,
    ip          VARCHAR(45)  NOT NULL,
    country     VARCHAR(100),
    city        VARCHAR(100),
    latitude    DOUBLE PRECISION,
    longitude   DOUBLE PRECISION,
    asn         VARCHAR(100),
    resolved    BOOLEAN      DEFAULT false,
    enriched_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_osint_ip        ON osint_records (ip);
CREATE INDEX IF NOT EXISTS idx_osint_threat_id ON osint_records (threat_id);

-- ─────────────────────────────────────────────────────────────────────────
-- Usuarios iniciales
-- Contraseña: NetWatch2024!  (BCrypt strength 12)
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO users (email, password_hash, role) VALUES
    ('admin@netwatch.local',
     '$2b$12$Bowplj7Z.Kd9OMOqYN7ide57FxYTGDs35llqgsXh3TJb9IHby661i',
     'ADMIN'),
    ('analista@netwatch.local',
     '$2b$12$Bowplj7Z.Kd9OMOqYN7ide57FxYTGDs35llqgsXh3TJb9IHby661i',
     'ANALYST')
ON CONFLICT (email) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────
-- Hardening: principio de mínimo privilegio para el usuario de aplicación
--
-- El usuario de la aplicación (netwatch) recibe solo los permisos DML
-- necesarios (SELECT, INSERT, UPDATE, DELETE). Se le revoca la capacidad
-- de crear o modificar el schema de la base de datos.
--
-- Los cambios de schema (DDL) solo los hace el script de inicialización
-- que se ejecuta como superusuario al arrancar el contenedor. Con
-- spring.jpa.hibernate.ddl-auto=validate la aplicación verifica el schema
-- pero nunca lo modifica en producción.
-- ─────────────────────────────────────────────────────────────────────────

-- Revocar capacidad de crear objetos en el schema public
REVOKE CREATE ON SCHEMA public FROM netwatch;

-- Garantizar permisos DML sobre todas las tablas existentes y futuras
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO netwatch;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO netwatch;

-- Aplicar los mismos permisos DML a tablas creadas en el futuro
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO netwatch;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO netwatch;
