-- migrate:up

CREATE TABLE log_collections (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT log_collections_name_nonempty CHECK (length(btrim(name)) >= 1),
    CONSTRAINT log_collections_name_length   CHECK (length(name) <= 200)
);

CREATE INDEX log_collections_user_idx
  ON log_collections (user_id, updated_at DESC);

ALTER TABLE logs
  ADD COLUMN collection_id TEXT REFERENCES log_collections(id) ON DELETE SET NULL;

CREATE INDEX logs_collection_idx
  ON logs (collection_id) WHERE collection_id IS NOT NULL;

-- migrate:down

DROP INDEX IF EXISTS logs_collection_idx;
ALTER TABLE logs DROP COLUMN IF EXISTS collection_id;
DROP INDEX IF EXISTS log_collections_user_idx;
DROP TABLE IF EXISTS log_collections;
