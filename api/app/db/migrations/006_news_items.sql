CREATE TABLE IF NOT EXISTS news_items (
    id SERIAL PRIMARY KEY,
    feed_name TEXT NOT NULL,
    title TEXT NOT NULL,
    url TEXT NOT NULL UNIQUE,
    description TEXT,
    published_at TIMESTAMPTZ,
    summary TEXT,
    summary_status TEXT NOT NULL DEFAULT 'pending',
    summary_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_news_items_published_at
    ON news_items (published_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_news_items_feed_name
    ON news_items (feed_name);
