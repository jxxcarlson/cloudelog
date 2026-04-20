-- migrate:up

-- logs: replace the scalar `unit` with parallel metric arrays.
ALTER TABLE logs
  ADD COLUMN metric_names TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN metric_units TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE logs SET
  metric_names = ARRAY[unit],
  metric_units = ARRAY[unit];

ALTER TABLE logs
  ADD CONSTRAINT logs_metrics_same_length
    CHECK (cardinality(metric_names) = cardinality(metric_units)),
  ADD CONSTRAINT logs_metrics_nonempty
    CHECK (cardinality(metric_names) >= 1),
  DROP COLUMN unit;

-- entries: replace the scalar quantity/description with parallel arrays.
ALTER TABLE entries
  ADD COLUMN quantities   DOUBLE PRECISION[] NOT NULL DEFAULT ARRAY[]::DOUBLE PRECISION[],
  ADD COLUMN descriptions TEXT[]             NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE entries SET
  quantities   = ARRAY[quantity],
  descriptions = ARRAY[description];

ALTER TABLE entries
  DROP COLUMN quantity,
  DROP COLUMN description;

-- migrate:down

ALTER TABLE entries
  ADD COLUMN quantity    DOUBLE PRECISION NOT NULL DEFAULT 0,
  ADD COLUMN description TEXT NOT NULL DEFAULT '';

UPDATE entries SET
  quantity    = quantities[1],
  description = descriptions[1];

ALTER TABLE entries
  DROP COLUMN quantities,
  DROP COLUMN descriptions;

ALTER TABLE logs
  DROP CONSTRAINT logs_metrics_nonempty,
  DROP CONSTRAINT logs_metrics_same_length,
  ADD COLUMN unit TEXT NOT NULL DEFAULT '';

UPDATE logs SET unit = metric_units[1];

ALTER TABLE logs
  ALTER COLUMN unit DROP DEFAULT,
  DROP COLUMN metric_names,
  DROP COLUMN metric_units;
