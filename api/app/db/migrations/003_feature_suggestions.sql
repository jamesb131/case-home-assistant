CREATE TABLE IF NOT EXISTS feature_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    title TEXT NOT NULL,
    description TEXT,
    source TEXT NOT NULL DEFAULT 'case_voice',
    status TEXT NOT NULL DEFAULT 'new'
);
