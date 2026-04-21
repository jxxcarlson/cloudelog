-- migrate:up

ALTER TABLE entries
  ADD CONSTRAINT entries_values_same_length
    CHECK (cardinality(quantities) = cardinality(descriptions)),
  ADD CONSTRAINT entries_values_nonempty
    CHECK (cardinality(quantities) >= 1);

-- migrate:down

ALTER TABLE entries
  DROP CONSTRAINT entries_values_nonempty,
  DROP CONSTRAINT entries_values_same_length;
