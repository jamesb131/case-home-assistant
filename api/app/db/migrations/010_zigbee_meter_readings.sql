CREATE TABLE IF NOT EXISTS zigbee_meter_readings (
    id BIGSERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    device_name TEXT NOT NULL,
    topic TEXT NOT NULL,
    payload_at TIMESTAMPTZ,
    state TEXT,
    power_w NUMERIC,
    energy_kwh NUMERIC,
    voltage_v NUMERIC,
    current_a NUMERIC,
    linkquality INTEGER,
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_zigbee_meter_readings_device_captured
    ON zigbee_meter_readings (device_name, captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_zigbee_meter_readings_captured_at
    ON zigbee_meter_readings (captured_at DESC);
