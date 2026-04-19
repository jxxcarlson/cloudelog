-- migrate:up

ALTER TABLE logs
    ADD COLUMN start_date DATE NOT NULL DEFAULT CURRENT_DATE;

-- migrate:down

ALTER TABLE logs DROP COLUMN IF EXISTS start_date;
