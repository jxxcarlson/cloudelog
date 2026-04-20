-- migrate:up

CREATE TABLE streaks (
    id          SERIAL PRIMARY KEY,
    log_id      TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
    start_date  DATE NOT NULL,
    length      INTEGER NOT NULL CHECK (length > 0),
    UNIQUE (log_id, start_date)
);

-- One-shot backfill for existing logs. After this, the backend owns the table.
-- Islands pattern: consecutive dates within a (log_id, qty>0) subset have
-- a constant (entry_date - row_number) value, so GROUP BY that difference
-- collapses each run into a single row.
INSERT INTO streaks (log_id, start_date, length)
SELECT
    log_id,
    MIN(entry_date) AS start_date,
    COUNT(*)        AS length
FROM (
    SELECT
        log_id,
        entry_date,
        entry_date - (ROW_NUMBER() OVER (PARTITION BY log_id ORDER BY entry_date))::int AS grp
    FROM entries
    WHERE quantity > 0
) t
GROUP BY log_id, grp;

-- migrate:down

DROP TABLE IF EXISTS streaks;
