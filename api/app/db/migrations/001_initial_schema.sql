CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sigenergy_raw_registers (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    device_id INTEGER NOT NULL,
    register_address INTEGER NOT NULL,
    register_count INTEGER NOT NULL,
    register_type TEXT NOT NULL,
    raw_registers INTEGER[] NOT NULL,
    decoded_value DOUBLE PRECISION,
    unit TEXT,
    label TEXT
);

CREATE INDEX IF NOT EXISTS idx_sigenergy_raw_registers_captured_at
    ON sigenergy_raw_registers (captured_at);

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

    ems_work_mode INTEGER,
    grid_sensor_status INTEGER,
    on_off_grid_status INTEGER,
    plant_running_state INTEGER
);

CREATE INDEX IF NOT EXISTS idx_energy_readings_captured_at
    ON energy_readings (captured_at);

CREATE TABLE IF NOT EXISTS household_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    list_type TEXT NOT NULL DEFAULT 'general',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_household_lists_name_lower
    ON household_lists (LOWER(name));

CREATE TABLE IF NOT EXISTS household_list_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id UUID NOT NULL REFERENCES household_lists(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    quantity TEXT,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_household_list_items_list_status
    ON household_list_items (list_id, status, sort_order, created_at);

CREATE TABLE IF NOT EXISTS task_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    title TEXT NOT NULL,
    description TEXT,
    assigned_to TEXT,
    recurrence_type TEXT NOT NULL DEFAULT 'weekly',
    day_of_week INTEGER,
    day_of_month INTEGER,
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date DATE,
    expires_after_days INTEGER,
    priority TEXT NOT NULL DEFAULT 'normal',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    source TEXT NOT NULL DEFAULT 'manual',
    visible_day_offset INTEGER NOT NULL DEFAULT 0,
    visible_time TIME,
    due_day_offset INTEGER NOT NULL DEFAULT 0,
    due_time TIME
);

CREATE INDEX IF NOT EXISTS idx_task_templates_active
    ON task_templates (active);

CREATE TABLE IF NOT EXISTS household_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    title TEXT NOT NULL,
    description TEXT,
    assigned_to TEXT,
    due_date DATE,
    status TEXT NOT NULL DEFAULT 'pending',
    priority TEXT NOT NULL DEFAULT 'normal',
    completed_at TIMESTAMPTZ,
    source TEXT NOT NULL DEFAULT 'manual',
    recurring_template_id UUID REFERENCES task_templates(id) ON DELETE SET NULL,
    occurrence_date DATE,
    expires_at DATE,
    expired_at TIMESTAMPTZ,
    visible_at TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_household_tasks_template_occurrence
    ON household_tasks (recurring_template_id, occurrence_date)
    WHERE recurring_template_id IS NOT NULL AND occurrence_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_household_tasks_status_due_date
    ON household_tasks (status, due_date);

CREATE INDEX IF NOT EXISTS idx_household_tasks_assigned_to
    ON household_tasks (assigned_to);

INSERT INTO household_lists (name, list_type, is_primary, sort_order)
VALUES
    ('Groceries', 'shopping', TRUE, 0),
    ('Bunnings', 'hardware', FALSE, 10)
ON CONFLICT (LOWER(name)) DO NOTHING;
