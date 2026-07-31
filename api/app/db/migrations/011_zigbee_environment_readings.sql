CREATE TABLE IF NOT EXISTS zigbee_environment_readings (
    id BIGSERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    device_name TEXT NOT NULL,
    topic TEXT NOT NULL,
    payload_at TIMESTAMPTZ,
    temperature_c NUMERIC,
    humidity_percent NUMERIC,
    battery_percent NUMERIC,
    voltage_mv NUMERIC,
    linkquality INTEGER,
    air_quality TEXT,
    co2_ppm NUMERIC,
    voc_index NUMERIC,
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_zigbee_environment_readings_device_captured
    ON zigbee_environment_readings (device_name, captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_zigbee_environment_readings_captured_at
    ON zigbee_environment_readings (captured_at DESC);
