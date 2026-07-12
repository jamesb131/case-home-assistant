CREATE TABLE IF NOT EXISTS system_snapshots (
    key TEXT PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'ok',
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    error TEXT
);

CREATE INDEX IF NOT EXISTS idx_system_snapshots_status
    ON system_snapshots (status);

CREATE INDEX IF NOT EXISTS idx_system_snapshots_expires_at
    ON system_snapshots (expires_at);

CREATE TABLE IF NOT EXISTS service_heartbeats (
    service_name TEXT PRIMARY KEY,
    heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT NOT NULL DEFAULT 'ok',
    details JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS energy_daily_rollups (
    day DATE PRIMARY KEY,
    solar_kwh DOUBLE PRECISION,
    grid_import_kwh DOUBLE PRECISION,
    grid_export_kwh DOUBLE PRECISION,
    house_load_kwh DOUBLE PRECISION,
    ev_charge_kwh DOUBLE PRECISION,
    battery_soc_min DOUBLE PRECISION,
    battery_soc_max DOUBLE PRECISION,
    reading_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
