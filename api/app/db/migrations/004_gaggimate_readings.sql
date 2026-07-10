CREATE TABLE IF NOT EXISTS gaggimate_readings (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    host TEXT NOT NULL,
    online BOOLEAN NOT NULL DEFAULT TRUE,
    current_temp_c DOUBLE PRECISION,
    target_temp_c DOUBLE PRECISION,
    pressure_bar DOUBLE PRECISION,
    flow_ml_s DOUBLE PRECISION,
    target_pressure_bar DOUBLE PRECISION,
    mode INTEGER,
    mode_label TEXT,
    profile_label TEXT,
    pressure_capable BOOLEAN,
    dimming_capable BOOLEAN,
    error TEXT,
    raw_payload JSONB
);

CREATE INDEX IF NOT EXISTS idx_gaggimate_readings_captured_at
    ON gaggimate_readings (captured_at);
