-- migrate:up

CREATE TABLE users (
    id              TEXT PRIMARY KEY,
    email           TEXT NOT NULL UNIQUE,
    pw_hash         TEXT NOT NULL,
    current_log_id  TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE logs (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    unit        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX logs_user_updated_idx ON logs (user_id, updated_at DESC);

ALTER TABLE users
    ADD CONSTRAINT users_current_log_fk
    FOREIGN KEY (current_log_id) REFERENCES logs(id) ON DELETE SET NULL;

CREATE TABLE entries (
    id          TEXT PRIMARY KEY,
    log_id      TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
    entry_date  DATE NOT NULL,
    quantity    DOUBLE PRECISION NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (log_id, entry_date)
);

CREATE INDEX entries_log_date_idx ON entries (log_id, entry_date);

-- migrate:down

DROP INDEX IF EXISTS entries_log_date_idx;
DROP TABLE IF EXISTS entries;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_current_log_fk;
DROP INDEX IF EXISTS logs_user_updated_idx;
DROP TABLE IF EXISTS logs;
DROP TABLE IF EXISTS users;
