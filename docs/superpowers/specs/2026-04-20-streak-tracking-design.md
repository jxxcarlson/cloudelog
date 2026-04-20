# Streak tracking

Date: 2026-04-20
Status: design approved, pending implementation plan

## Summary

For each log, track streaks — maximal runs of consecutive dates whose entry
has `quantity > 0`. Persist one row per streak in a new `streaks` table, kept
in sync with the `entries` table via recompute-on-write. Expose three
aggregates (`current`, `average`, `longest`) on the log-detail response, and
render a new row in `LogView` below the existing
`Days | Skipped | Total | Avg` stats.

## Motivation

The existing stats row answers "how much have you logged?" but not "how
consistent have you been?". Streaks surface consistency directly: the current
run the user is on, their average run length, and their personal best. They
are also the natural anchor for future features (milestone badges, streak
alerts, calendar highlighting).

## Design decisions (from brainstorming)

1. **Streak definition.** A streak is a maximal run of consecutive dates
   (`log_id` fixed) where every date has an entry with `quantity > 0`. A gap
   (missing row) or a `quantity = 0` row breaks the run.
2. **"Current streak" = length of the most-recent streak**, regardless of
   whether today was skipped. Rest-day tolerant: taking a day off doesn't
   zero the headline number. A new streak only starts once the user logs
   `quantity > 0` again.
3. **"Average streak" includes the most-recent streak** in the arithmetic
   mean over all streak rows. Rejected the alternative of excluding the
   "open" streak: when a user has one streak of length 3, showing
   `avg 3, longest 3, current 3` is more satisfying than `avg —, longest 3,
   current 3`.
4. **Materialized table, recompute on every entry write.** Rejected
   compute-on-read (contradicts the spec, wasted CPU on every log view) and
   incremental merge/split (complex, easy to drift).
5. **Wire format is aggregates, not raw streak rows.** The UI needs three
   numbers; the raw table is server-side bookkeeping. If a future feature
   wants a streak timeline, we can switch to sending `streaks: [...]` then.
6. **Zero-length streaks aren't stored.** A `CHECK (length > 0)` enforces
   this — a "streak of zero" is a gap, not a streak.

## Data model

One migration (`003_add_streaks.sql`):

```sql
-- migrate:up

CREATE TABLE streaks (
    id          TEXT PRIMARY KEY,
    log_id      TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
    start_date  DATE NOT NULL,
    length      INTEGER NOT NULL CHECK (length > 0),
    UNIQUE (log_id, start_date)
);

CREATE INDEX streaks_log_idx ON streaks (log_id);

-- Backfill from existing entries. Runs once; after this, the recompute
-- function in the backend owns the table.
--
-- (Implemented as a SQL function or a one-off script — see implementation
-- plan.)

-- migrate:down

DROP INDEX IF EXISTS streaks_log_idx;
DROP TABLE IF EXISTS streaks;
```

- `ON DELETE CASCADE` — deleting a log drops its streaks.
- `UNIQUE (log_id, start_date)` — exactly one streak per start date per log.
- `CHECK (length > 0)` — no zero-length rows.

## Recompute algorithm

Given a `log_id`, inside a single transaction:

1. `DELETE FROM streaks WHERE log_id = $1`.
2. Load `SELECT entry_date, quantity FROM entries WHERE log_id = $1 ORDER BY
   entry_date ASC`.
3. Walk the list. Maintain `(runStart, runLength)`. For each entry:
   - If `quantity > 0` and this date is exactly `prevDate + 1 day` (or the
     first entry), extend the run (`runLength += 1`).
   - If `quantity > 0` but there's a gap, flush the current run (if any) and
     start a new one at this date.
   - If `quantity = 0`, flush the current run (if any).
4. Flush the final run at end-of-list.
5. Insert one row per flushed run.

Pseudocode:

```
streaks = []
cur = None           -- Maybe (Day, Int)
prevDate = None
for (date, qty) in entries_ordered:
    if qty > 0:
        if cur is None or date != prevDate + 1:
            if cur is not None: streaks.append(cur)
            cur = (date, 1)
        else:
            cur = (cur.start, cur.length + 1)
    else:  -- qty == 0
        if cur is not None: streaks.append(cur); cur = None
    prevDate = date
if cur is not None: streaks.append(cur)
```

The recompute runs inside the same DB transaction as the triggering entry
mutation (`POST /api/logs/:id/entries`, `PUT /api/entries/:id`,
`DELETE /api/entries/:id`). Failure rolls back both.

## API shape

`GET /api/logs/:id` already returns a `LogDetailResponse`:

```haskell
data LogDetailResponse = LogDetailResponse
  { ldrLog     :: LogResponse
  , ldrEntries :: [EntryResponse]
  }
```

Add one field:

```haskell
data StreakStats = StreakStats
  { ssCurrent :: Int
  , ssAverage :: Maybe Double  -- Nothing when no streaks exist
  , ssLongest :: Int
  }

data LogDetailResponse = LogDetailResponse
  { ldrLog         :: LogResponse
  , ldrEntries     :: [EntryResponse]
  , ldrStreakStats :: StreakStats
  }
```

Wire format (via `stripPrefixOptions`):

```json
{
  "log": {...},
  "entries": [...],
  "streakStats": { "current": 12, "average": 5.4, "longest": 17 }
}
```

Empty-log case: `{ "current": 0, "average": null, "longest": 0 }`.

`StreakStats` is computed from the `streaks` table at response time (one
`SELECT` aggregates all three values; it's cheap).

## Frontend

In `LogView.elm`:

- `Api.elm` `logDetailDecoder` gains a `streakStats` field (new Elm type
  `StreakStats`).
- `LogView.Model` gains `streakStats : Maybe StreakStats` (populated when the
  log detail loads alongside entries).
- A new view helper `viewStreakStats` renders a sibling row to the existing
  `div.stats` (`LogView.elm:461-466`):

  ```
  Days | Skipped | Total | Avg
  Current streak | Avg streak | Longest streak
  ```

  Same `class "stats"`, same 4-column-ish layout (three cells, one empty or
  re-use the same grid — implementation plan to pick). `"—"` shown for
  `null`/`0` values. Insertion point: immediately after the existing
  `viewStats stats` call at `LogView.elm:340`.

- No frontend computation. Streaks are not derived client-side from
  `entries`.

## Testing

**Haskell unit tests** for the streak computation function. Cases:

- Empty entry list → `[]`.
- All-zero entries → `[]`.
- Single `qty > 0` entry → one streak of length 1.
- Alternating `qty > 0` and `qty = 0` → many one-day streaks.
- One uninterrupted run of 5 → one streak of length 5.
- Run with a one-day gap (missing date) in the middle → two streaks.
- Run broken by a `qty = 0` entry → two streaks.
- Run ending on today, not yet broken → length reflects through today.

**E2E tests** in `test-api.sh`:

- Create log, post three consecutive `qty > 0` entries, `GET /api/logs/:id`
  → `streakStats.current == 3`, `longest == 3`, `average == 3`.
- Post a `qty = 0` entry for the next day → `current == 3` still (rest-day
  tolerant per decision #2).
- Post another `qty > 0` entry the day after → `current == 1`, `longest == 3`,
  `average == 2`.
- Delete the middle `qty = 0` entry → streaks merge (recompute verified):
  `current == 5`, `longest == 5`, `average == 5`. *(Only valid if deleting a
  skip row leaves no gap; backfill semantics apply — confirm in
  implementation plan.)*
- Update an existing `qty > 0` entry to `qty = 0` → current streak shrinks
  or splits accordingly.

## Non-goals

- Surfacing individual streak rows to the client.
- Streak milestone badges or notifications.
- Per-streak annotations or naming.
- Streak charts / calendar highlighting.

All achievable later without schema changes.

## Open items for the implementation plan

- Exact placement of the backfill step in migration 003 (SQL vs. one-shot
  Haskell script).
- Name of the recompute helper in the backend (`Db.Streaks.recompute`?
  `Service.Streak.recompute`?) and where the computation function lives.
- Deletion semantics in the middle of a backfilled skip run — confirm that
  the delete handler's post-invariant is consistent with streak recompute.
- Grid layout for the new stats row (reuse `class "stats"` or introduce
  `class "streak-stats"`).
