CREATE TABLE IF NOT EXISTS energy_readings (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    solar_kw DOUBLE PRECISION,
    inverter_pv_kw DOUBLE PRECISION,
    inverter_temp_c DOUBLE PRECISION,

    battery_soc DOUBLE PRECISION,
    battery_soh DOUBLE PRECISION,
    battery_kw DOUBLE PRECISION,
    battery_usable_kwh DOUBLE PRECISION,
    battery_capacity_kwh DOUBLE PRECISION,

    grid_kw DOUBLE PRECISION,
    grid_a_kw DOUBLE PRECISION,
    grid_b_kw DOUBLE PRECISION,
    grid_c_kw DOUBLE PRECISION,
    grid_connected BOOLEAN,
    grid_supplying_house BOOLEAN,
    grid_exporting BOOLEAN,

    house_load_kw DOUBLE PRECISION,
    ev_kw DOUBLE PRECISION,
    ev_total_kwh DOUBLE PRECISION,

    ems_work_mode INTEGER,
    grid_sensor_status INTEGER,
    on_off_grid_status INTEGER,
    plant_running_state INTEGER
);
