CREATE TABLE IF NOT EXISTS calendar_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    source_type TEXT NOT NULL,
    external_id TEXT,
    url TEXT,
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    refresh_interval_seconds INTEGER NOT NULL DEFAULT 1800,
    last_synced_at TIMESTAMPTZ,
    last_success_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source_type, external_id)
);

CREATE TABLE IF NOT EXISTS calendar_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID NOT NULL REFERENCES calendar_sources(id) ON DELETE CASCADE,
    external_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    start_at TIMESTAMPTZ,
    end_at TIMESTAMPTZ,
    start_date DATE,
    end_date DATE,
    is_all_day BOOLEAN NOT NULL DEFAULT FALSE,
    category TEXT,
    audience TEXT,
    url TEXT,
    source_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (source_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_calendar_events_start_at
    ON calendar_events (start_at);

CREATE INDEX IF NOT EXISTS idx_calendar_events_start_date
    ON calendar_events (start_date);

CREATE INDEX IF NOT EXISTS idx_calendar_events_source_last_seen
    ON calendar_events (source_id, last_seen_at);
