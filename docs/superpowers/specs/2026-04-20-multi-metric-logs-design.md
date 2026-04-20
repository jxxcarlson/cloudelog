# Multi-metric logs

Date: 2026-04-20
Status: design approved, pending implementation plan

## Summary

A log becomes a container for an ordered, named list of **metrics**, each with
its own unit. An entry carries one `(quantity, description)` pair per metric,
aligned by position. Most logs will have a single metric (status quo); the
structure expands to accommodate logs like "Running" that naturally track
parallel numeric measurements (distance, time, heart rate).

Storage uses Postgres parallel arrays on the existing `logs` and `entries`
tables — one row per log, one row per entry, with the arrays holding the
per-metric values.

## Motivation

The current one-quantity-per-entry schema forces the user to split naturally
correlated measurements into separate logs (e.g., a "Running distance" log
and a "Running time" log), which in turn scatters streaks, stats, and the
conceptual unit of a single activity across multiple pages. Multi-metric logs
keep the activity as one log while preserving the ability to see each
metric's total/average independently.

## Design decisions (from brainstorming)

1. **Named metrics.** Each metric is `{ name, unit }`, not just a bare unit.
   Rationale: removes ambiguity when two metrics share a unit (e.g., two
   "count" metrics), and reads more naturally in the UI ("distance: 3.2
   miles" vs "miles: 3.2").
2. **"Any metric > 0" defines a streak day.** A day counts toward a streak
   iff at least one metric has quantity > 0 on that day. Generalization of
   the prior single-metric rule. Rejected alternatives: first-metric-only
   (arbitrary privilege), user-designated primary (extra UI for little gain
   at current scope).
3. **Parallel arrays.** `logs` stores `metric_names TEXT[]` +
   `metric_units TEXT[]`; `entries` stores `quantities DOUBLE PRECISION[]` +
   `descriptions TEXT[]`. Alignment is by position. Rejected alternative:
   child tables (`log_metrics`, `entry_values`) — overkill for the
   small-N-per-log case and would force joins on every read.
4. **Stats UI: shared Days/Skipped, per-metric Total/Avg.** Days and Skipped
   are inherently per-day log-wide facts; Total and Avg are per-metric.
   Rejected alternatives: one full stats row per metric (tall for N ≥ 3),
   or only the first metric (loses information).
5. **Descriptions are per-metric.** Each `(quantity, description)` pair is
   kept together. A user who wants a single note per day writes it on the
   first metric and leaves the rest empty.
6. **Rename always; structural edits only on empty logs.** Renaming a metric
   is a no-op on the data layer and is always permitted. Adding, removing,
   reordering, or changing the unit of a metric is only allowed when the log
   has zero entries — the same safety net as the old "unit immutable once
   entries exist" rule, lifted to N metrics.

## Data model

### `logs` changes

```sql
ALTER TABLE logs
  ADD COLUMN metric_names TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN metric_units TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD CONSTRAINT logs_metrics_same_length
    CHECK (cardinality(metric_names) = cardinality(metric_units)),
  ADD CONSTRAINT logs_metrics_nonempty
    CHECK (cardinality(metric_names) >= 1);

-- Backfill from the existing scalar `unit`. The metric's name defaults to
-- its unit string; the user can rename later.
UPDATE logs SET
  metric_names = ARRAY[unit],
  metric_units = ARRAY[unit];

ALTER TABLE logs DROP COLUMN unit;
```

### `entries` changes

```sql
ALTER TABLE entries
  ADD COLUMN quantities   DOUBLE PRECISION[] NOT NULL DEFAULT ARRAY[]::DOUBLE PRECISION[],
  ADD COLUMN descriptions TEXT[]             NOT NULL DEFAULT ARRAY[]::TEXT[];

UPDATE entries SET
  quantities   = ARRAY[quantity],
  descriptions = ARRAY[description];

ALTER TABLE entries DROP COLUMN quantity, DROP COLUMN description;
```

### Application-layer invariant

`length(entries.quantities) == length(entries.descriptions) ==
length(logs.metric_names)` for every entry of a given log. Enforced in the
handler at ingress (not by a DB constraint, since cross-table CHECK requires
triggers).

## API shape

`LogResponse`:

```json
{
  "id": "...",
  "name": "Running",
  "description": "weekday morning runs",
  "metrics": [
    { "name": "distance", "unit": "miles" },
    { "name": "time",     "unit": "minutes" }
  ],
  "startDate": "2026-04-20",
  "createdAt": "...",
  "updatedAt": "..."
}
```

`EntryResponse`:

```json
{
  "id": "...",
  "logId": "...",
  "entryDate": "2026-04-20",
  "values": [
    { "quantity": 3.2,  "description": "easy recovery" },
    { "quantity": 27.5, "description": "" }
  ],
  "createdAt": "...",
  "updatedAt": "..."
}
```

`CreateLogRequest`:

```json
{
  "name": "Running",
  "description": "...",
  "metrics": [
    { "name": "distance", "unit": "miles" },
    { "name": "time",     "unit": "minutes" }
  ],
  "startDate": "2026-04-20"
}
```

`UpdateLogRequest` is the same shape. The handler enforces the
edit-permissibility rules from decision 6 (see below).

`CreateEntryRequest` (POST `/api/logs/:id/entries`):

```json
{
  "entryDate": "2026-04-20",
  "values": [
    { "quantity": 3.2,  "description": "easy recovery" },
    { "quantity": 27.5, "description": "" }
  ]
}
```

`UpdateEntryRequest` (PUT `/api/entries/:id`):

```json
{
  "values": [
    { "quantity": 3.2,  "description": "easy recovery" },
    { "quantity": 27.5, "description": "" }
  ]
}
```

The wire format uses an array-of-objects for readability; the DB uses two
parallel arrays for storage simplicity. The handler zips/unzips at the
boundary.

### Request validation

- `metrics` must be non-empty.
- Each metric must have a non-empty `name` (after trim) and a non-empty `unit`
  (after trim, max 32 chars — same as today).
- `values.length == metrics.length` or 400 "values must have N entries (got
  M)".
- Each `quantity` must be finite and ≥ 0 (same rule as today, per element).

## Metric editability (`PUT /api/logs/:id`)

Given an existing log and an incoming `UpdateLogRequest.metrics`:

1. **Rename (structural match, name differs):** always allowed. Compare
   `metric_units` position-wise — if the unit arrays match exactly, only
   names changed, and the update proceeds regardless of entry count.
2. **Structural change (length differs, order differs, or any unit
   changes):** allowed only if `countLogEntries(log_id) == 0`. Otherwise
   400 "Cannot change metric structure of a log that has entries".
3. **Unknown/missing field:** if the request omits `metrics` entirely, the
   log's metrics are left unchanged (partial-update behavior for the rest
   of the fields). This matches the existing pattern for `unit`.

## Streak logic update

The pure `Service.Streak.computeStreaks` signature changes:

```haskell
-- was: [(Day, Double)] -> [(Day, Int)]
computeStreaks :: [(Day, [Double])] -> [(Day, Int)]
-- A day is "active" iff any quantity in the list is > 0.
-- A gap or an all-zero day breaks the run.
```

`Db.Streak.selectEntryDateQuantity` changes to:

```sql
SELECT entry_date, quantities FROM entries
WHERE log_id = $1 ORDER BY entry_date ASC
```

Decoder decodes the `quantities` array into `[Double]`. Helper in
`Service.Streak` (or inline at the call site): `anyPositive :: [Double] ->
Bool` for clarity.

The `recomputeStreaksTx` helper, the `streaks` table schema, and the
`StreakStats` response are all unchanged — they're downstream of the
pure function.

## Skip-fill

`insertSkipFills` inserts a day's entry with `quantities = [0, 0, ..., 0]`
and `descriptions = ["", "", ..., ""]`, both of length = the log's metric
count. The handler reads the log's metric count inside the same transaction
(via `FOR UPDATE` — already held) and passes it as a parameter to the bulk
insert.

SQL sketch:

```sql
INSERT INTO entries (id, log_id, entry_date, quantities, descriptions)
SELECT
  unnest($2 :: text[]),                        -- pre-generated UUIDs
  $1,                                          -- log_id
  unnest($3 :: date[]),                        -- fill dates
  array_fill(0::double precision, ARRAY[$4]),  -- zero quantities, length $4
  array_fill(''::text,           ARRAY[$4])    -- empty descriptions, length $4
ON CONFLICT (log_id, entry_date) DO NOTHING
```

where `$4` is the log's metric count (fetched via `array_length(metric_names,
1)` at preflight or inside the transaction).

## Stats (UI, computed client-side)

```
Days: 30 | Skipped: 3
distance — Total: 96.4 miles | Avg: 3.6 miles/day
time     — Total: 810 min    | Avg: 30 min/day
```

Rendered as:

- Row 1: `div.stats` with Days + Skipped (no unit).
- Row 2..N+1: `div.stats` per metric — metric name, Total, Avg (both
  suffixed with the metric's unit).
- Row N+2: the streak row (`Current / Avg / Longest`), unchanged.

`LogView.computeStats` is generalized to return a per-metric breakdown:

```elm
type alias Stats =
    { days : Int
    , skipped : Int
    , perMetric : List MetricStats
    }

type alias MetricStats =
    { name : String
    , unit : String
    , total : Float
    , average : Maybe Float
    }
```

`skipped` is re-defined as "entries where every quantity is 0" (matches the
skip-fill invariant).

## Frontend

### Types

```elm
-- Types.elm
type alias Metric =
    { name : String, unit : String }

type alias Log =
    { id : String
    , name : String
    , description : String
    , metrics : List Metric
    , startDate : Date
    , createdAt : Posix
    , updatedAt : Posix
    }

type alias EntryValue =
    { quantity : Float, description : String }

type alias Entry =
    { id : String
    , logId : String
    , date : Date
    , values : List EntryValue
    }
```

`Unit` (the four-case enum) is retired — units are now free-form strings.
Unit normalization (lowercasing "minutes"/"hours"/"kilometers"/"miles")
stays on the backend.

### New-log form

- Default: one empty metric row (`{ name = "", unit = "" }`).
- "Add another metric" button appends a row.
- "Remove" button on each row (disabled when there's only one left).
- Name field autofocuses on the first row; unit field is the second input
  per row.

### Entry form

- N parallel `(quantity, description)` input pairs — one pair per metric.
- Each pair's label is the metric's name; the quantity input is suffixed
  with the metric's unit.
- Submit builds the `values` array positionally.

### Entry editing (inline in LogView)

- The existing inline edit form generalizes: N pairs of inputs, positional.

### LogView stats

- Uses the new `MetricStats` breakdown described above.
- Streak row (`Current / Avg / Longest`) stays unchanged.

## Non-goals

- Per-metric streaks (only the log-wide "any active" streak exists).
- Per-metric start-date or backfill behavior (all metrics share the log's
  `start_date`).
- Metric reordering or restructuring on non-empty logs — if a user needs it,
  they create a new log or clear entries first.
- Derived / computed metrics (e.g., "pace = time / distance"). Could be added
  later without schema change.
- Bulk import of multi-metric data. Manual entry only in this pass.

## Open items for the implementation plan

- Exact shape of the migration script: single migration that adds arrays,
  backfills, and drops the old columns, or split into "expand" (add arrays,
  backfill, keep old cols) and "contract" (drop old cols) migrations. For a
  solo-operator production, a single migration is fine; split helps in a
  zero-downtime deploy.
- Whether to enforce uniqueness of metric names within a log
  (`UNIQUE (log_id, name)` via a CHECK or an application-layer validation).
  Leaning toward application-layer: the array storage doesn't naturally
  support a UNIQUE on an element.
- Handling of the existing `users.current_log_id` on migration: no change
  needed (it's a log ID, not metric-aware).
- Frontend affordance for "single-metric logs": the "Add another metric"
  button should be visible but unobtrusive; the first metric's form row
  should read naturally without looking list-like when N = 1.
