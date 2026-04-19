# Log start date

Date: 2026-04-19
Status: design approved, pending implementation plan

## Summary

Add an optional "start date" to each log. When a user creates a log with
`startDate = d1` and today is `d2 > d1`, the server backfills zero-quantity
skip entries for every date `d` such that `d1 <= d < d2`. These backfilled
entries are regular rows and editable via the existing `PUT /api/entries/:id`.

## Motivation

Today, a log starts empty on the day it's created. If a user realizes mid-week
that they want to log something retroactively, they have no clean way to
record "I meant to start tracking this on Monday; nothing happened since
then." The start date makes that explicit and anchors the log's timeline.

## Design decisions (from brainstorming)

1. **Persistent column**, not transient input. `start_date` lives on the
   `logs` table so the log carries its "since" semantically.
2. **Reject future start dates.** `start_date > today` returns 400.
3. **Immutable after creation.** No endpoint updates `start_date`.
4. **Form defaults handled server-side.** If the client omits `startDate`,
   the server uses `CURRENT_DATE`. No client-side "today" plumbing required.

## Data model

One migration:

```sql
ALTER TABLE logs
  ADD COLUMN start_date DATE NOT NULL DEFAULT CURRENT_DATE;
```

- `NOT NULL` — every log has a start date.
- Existing rows get today as their start date. Acceptable in this dev
  project because existing logs are test data. If we later need to backfill
  more accurately, one `UPDATE logs SET start_date = (SELECT MIN(entry_date)
  FROM entries WHERE entries.log_id = logs.id) WHERE ...` would do it.

Haskell `Types.Log.Log` gains `logStartDate :: Day`. Response type
`LogResponse` gains `logrStartDate :: Day` (serializes to `startDate` via the
existing `stripPrefixOptions` mechanism).

## Create-log flow

`POST /api/logs` request body gains one optional field:

```json
{ "name": "...", "unit": "...", "description": "...", "startDate": "2026-04-16" }
```

- If `startDate` is absent → server uses `CURRENT_DATE`.
- If `startDate` is present and `> today` → 400 "start date cannot be in the future".
- Existing name/unit validation unchanged.

Server performs both the log insert and the skip backfill in a single
`Tx.Serializable Tx.Write` transaction:

1. `INSERT INTO logs (..., start_date) VALUES (..., $startDate) RETURNING ...`
2. Compute `fillDays = [startDate, startDate+1, ..., today-1]` (empty if
   `startDate == today`). Implementation note: `datesToFill (Just (startDate - 1))
   today` already yields exactly this list — reuse rather than introduce a new
   helper.
3. If `fillDays` is non-empty, pre-generate that many UUIDs and call the
   existing `Db.Entry.insertSkipFills` statement (zero quantity, empty
   description, `ON CONFLICT DO NOTHING`).
4. Return the created `LogResponse` (now including `startDate`).

Nothing on the entry-posting path changes. When the user later adds a real
entry on date `d_new`, the existing `maxEntryDate` + `datesToFill` pipeline
fills any gap between the last backfilled date (`today - 1`) and `d_new - 1`.
The two skip-fill mechanisms compose without coordination.

## Entry editing

Skip entries are plain `entries` rows. The existing `PUT /api/entries/:id`
already updates quantity and description and is the only endpoint needed.
No changes here.

## Frontend

**Types** (`frontend/src/Types.elm`): `Log` and `LogSummary` gain
`startDate : Date`.

**API** (`frontend/src/Api.elm`):
- `createLog` signature accepts an optional `startDate : Maybe String` (ISO
  string). Request body includes `"startDate": ...` only when non-empty, so
  omitted lets the server default.
- `logDecoder` / `logSummaryDecoder` decode the new field using the existing
  `dateDecoder`.

**New-log form** (`frontend/src/LogList.elm`):
- `NewLogForm` gains `startDate : String` (raw ISO string from the
  `<input type="date">` element). Default empty string.
- UI: `<input type="date">` labeled "Start date (optional, defaults to today)".
  Blank means "use today."
- On submit: pass `Nothing` if blank, else `Just form.startDate`.
- If server returns 400 (future date), surface via existing `error` field /
  flash.

**Log view** (`frontend/src/LogView.elm`):
- Display "since YYYY-MM-DD" in the log header, one line. Source: `log.startDate`.

**Log list row** (`frontend/src/LogList.elm viewRow`): unchanged.

## Testing

**Unit tests (`backend/test/`):** existing `SkipFillSpec` remains unchanged.
The reuse of `datesToFill (Just (startDate - 1)) today` is covered by its
existing properties (return empty when `newD <= lastD + 1`, otherwise all
days strictly between); no new unit tests required.

**End-to-end (`backend/test-api.sh`):** add four cases near the top, after
signup and before the existing log-creation block:

1. Create log with `startDate` three days before today. Fetch the log;
   assert `entries.length == 3`, all `quantity == 0`, `description == ""`,
   dates are d1, d1+1, d1+2, and the response `startDate` echoes d1.
2. Create log without `startDate`. Assert response `startDate == today` and
   `entries.length == 0`.
3. Create log with `startDate = today + 1`. Assert HTTP 400.
4. Edit one backfilled skip entry via `PUT /api/entries/:id` with
   `quantity=20, description="late edit"`. Assert the returned row has those
   values. (Confirms skip entries are editable with no new machinery.)

**Frontend tests:** none added. The change is plumbing — a string field
through the form and a new decoded field on `Log`. The e2e test plus manual
verification covers behavior.

## Out of scope

- Editing `start_date` after creation.
- Preventing entries with dates earlier than `start_date`.
- Displaying a streak or calendar view that uses `start_date` as an anchor.
- Backfilling `start_date` on existing logs from their earliest entry.

Any of these can be follow-up work without reshaping the data model.
