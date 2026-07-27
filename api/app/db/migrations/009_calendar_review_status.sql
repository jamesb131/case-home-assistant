ALTER TABLE calendar_events
    ADD COLUMN IF NOT EXISTS review_status TEXT NOT NULL DEFAULT 'approved',
    ADD COLUMN IF NOT EXISTS review_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_calendar_events_review_status
    ON calendar_events (review_status);
