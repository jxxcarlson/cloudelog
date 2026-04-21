# Log collections

Date: 2026-04-21
Status: design approved, pending implementation plan

## Summary

A **log collection** is a named, user-owned grouping of related logs — e.g.
a piano student's "Piano practice" collection containing `Sight reading`,
`Harmony`, `Improvisation`, `Repertoire`. Each member log remains a
first-class, independent log (its own streak, history, metrics) but gains
shared surfaces: a combined entry form for recording a day's activity
across all members in one submit, a per-unit combined totals summary, and
a date-grouped history that interleaves every member's entries.

Membership is at-most-one: a log belongs to zero or one collection. The
concept layers cleanly on top of the existing multi-metric work without
replacing or changing it.

## Motivation

The existing data model treats every log as standalone. Users with naturally
grouped practice patterns — piano practice, cardio training, language
study — have to navigate between 3-5 log detail pages to record a single
session, and lose any cross-log view of "how much total practice did I
do this week". Collections give that grouping first-class status while
preserving each log's identity and stats.

## Design decisions (from brainstorming)

1. **Collections are a grouping layer, not a replacement for multi-metric
   logs.** Multi-metric bundles per-activity measurements (distance + time
   for one run). Collections group per-discipline logs that are recorded
   independently (Sight reading today but not Harmony).
2. **Each log belongs to at most one collection.** Nullable `collection_id`
   on `logs`. A log without a collection appears on the main logs list as
   today. Rejected: many-to-many (adds a join table and management UI
   without a motivating use case); mandatory collection with an
   "Uncategorized" default (forces a concept users didn't ask for).
3. **Combined entry form on the collection page.** Submitting creates one
   entry per log for the given date, in a single transaction. Individual
   log pages keep their own add-entry form for one-off adds. Rejected:
   read-only summary (forces 4 clicks to record one piano session).
4. **Blank rows in the combined form become skip entries (qty=0) on
   submit.** Keeps member logs' timelines parallel and the combined
   stats coherent. Rejected: creating nothing for blank rows (would
   desync `Days` counts across the collection's member logs).
5. **Any log can be a member, including multi-metric logs. Combined
   totals aggregate by unit across every (log, metric) pair.** A
   collection with `Sight reading (min)`, `Running (km, min)`,
   `Cycling (km)` produces two combined rows: a `min` total summing
   Sight reading and Running's time, a `km` total summing Running's
   distance and Cycling. Rejected: single-metric-only (artificial),
   first-metric-only (silent data loss on metrics 2+).
6. **Collections appear on the main `/logs` page, above a flat list of
   standalone logs.** No new top-level navigation. Rejected: a separate
   `/collections` page (splits attention); forcing every log into a
   collection (backwards-incompatible).
7. **No collection-level streak.** Each member log keeps its own streak
   (the per-log feature we just shipped); the collection page renders
   those side-by-side. Can be added later as additive.
8. **Collection's effective start date = `MIN(logs.start_date)` across
   members, computed on read.** No `start_date` column on the collection
   itself — avoids desync between collection and member dates.
9. **Deleting a collection releases its logs to standalone** (`ON DELETE
   SET NULL` on `logs.collection_id`). Member logs and their entries
   survive.

## Data model

### New table

```sql
CREATE TABLE log_collections (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX log_collections_user_idx ON log_collections (user_id, updated_at DESC);
```

### Extend `logs`

```sql
ALTER TABLE logs
  ADD COLUMN collection_id TEXT REFERENCES log_collections(id) ON DELETE SET NULL;
CREATE INDEX logs_collection_idx ON logs (collection_id) WHERE collection_id IS NOT NULL;
```

- Default `NULL` for every existing row — no behavior change for current
  users.
- Partial index saves space; the majority of logs will be standalone.

### Application-layer invariants

- A collection may be empty (legal state while user is assembling members).
- All members of a collection belong to the same user (enforced by the
  handler on assignment).

## Membership semantics

**Create a collection.** `POST /api/collections` with `{ name, description? }`.
Empty collection is returned; the user assigns logs in a follow-up step.

**Assign or move a log.** `PUT /api/logs/:id` accepts a new optional
`collectionId :: Maybe Text`:

- `null` → release to standalone.
- A collection id owned by the same user → move in.
- A collection id owned by a different user → 403.
- An unknown collection id → 404 (the log is not modified).

**Rename / describe.** `PUT /api/collections/:id` with `{ name, description }`.

**Delete.** `DELETE /api/collections/:id`. Member logs are released via the
foreign key's `ON DELETE SET NULL`; the collection row is gone; members
and their entries and streaks all survive.

**Moving between collections.** Same `PUT /api/logs/:id` — just set the new
`collectionId`.

## API shape

| Method   | Path                              | Body                                        | Response                              |
|----------|-----------------------------------|---------------------------------------------|---------------------------------------|
| `POST`   | `/api/collections`                | `{ name, description? }`                    | `CollectionResponse`                  |
| `GET`    | `/api/collections`                | —                                           | `[CollectionSummaryResponse]`         |
| `GET`    | `/api/collections/:id`            | —                                           | `CollectionDetailResponse`            |
| `PUT`    | `/api/collections/:id`            | `{ name, description }`                     | `CollectionResponse`                  |
| `DELETE` | `/api/collections/:id`            | —                                           | `204`                                 |
| `POST`   | `/api/collections/:id/entries`    | `{ entryDate, logEntries: [...] }`          | `CollectionDetailResponse`            |

Plus the one extension:

- `PUT /api/logs/:id` gains `{ ..., "collectionId": null | "<id>" }`.
  Absent field = no change (same partial-update pattern used for `metrics`).

### `CollectionResponse` / `CollectionSummaryResponse`

```json
{
  "id": "...",
  "name": "Piano practice",
  "description": "Daily piano work",
  "createdAt": "...",
  "updatedAt": "..."
}
```

Summary adds `memberCount :: Int` (computed — `SELECT COUNT(*) FROM logs
WHERE collection_id = $1`).

### `CollectionDetailResponse`

```json
{
  "collection": { "id": "...", "name": "...", "description": "...",
                   "createdAt": "...", "updatedAt": "..." },
  "members": [
    { "log": {...LogResponse...}, "entries": [...], "streakStats": {...} },
    ...
  ]
}
```

Each `members[i]` has the same shape as the existing `LogDetailResponse`
(minus the outer `log`/`entries`/`streakStats` wrapper — each member is
itself a `LogDetailResponse`-shaped record). The frontend reuses the
existing decoders for every member.

Members are ordered by `logs.created_at ASC` so the UI order is stable.

### `POST /api/collections/:id/entries` — combined entry

```json
{
  "entryDate": "2026-04-21",
  "logEntries": [
    { "logId": "...", "values": [{ "quantity": 15, "description": "Clementi" }] },
    { "logId": "...", "values": [{ "quantity":  0, "description": "" }] },
    { "logId": "...", "values": [{ "quantity": 10, "description": "Blues in C" }] },
    { "logId": "...", "values": [{ "quantity": 30, "description": "Bach" }] }
  ]
}
```

**Transaction body (single `Tx.Serializable Tx.Write`):**

1. Verify the collection belongs to the caller (via `users.id = :user_id`
   join). If not, abort with 403.
2. For each item in `logEntries`:
   - Verify the `logId` is a member of this collection (400 with a message
     naming the offending id otherwise).
   - Verify `values.length == cardinality(logs.metric_units)` for that
     log (400 otherwise).
   - Compute skip-fill days between the log's last entry and `entryDate`
     (reuse the existing `Service.SkipFill.datesToFill`).
   - Insert skip-fills.
   - Upsert the actual entry (existing `DbEntry.upsertEntry` semantics:
     overwrite-on-conflict post the Task 2 migration).
   - Recompute streaks for the log (existing `recomputeStreaksTx`).
3. Load the fresh `CollectionDetailResponse` and return it.

**Blank-row encoding.** The frontend emits `quantity=0, description=""`
for every metric of a log the user left blank. The backend doesn't guess
— the client knows which rows the user intended as skips.

**Future-date guard.** `entryDate > today` → 400, consistent with the
existing individual-entry rule.

## UI

### Main logs page (`/logs`)

Two sections (rendered in this order; each hidden when empty):

```
[+ New log]   [+ New collection]

Collections
  ▸ Piano practice  (4 logs)  — Sight reading · Harmony · Improvisation · Repertoire
  ▸ Cardio          (2 logs)  — Running · Cycling

Logs
  Walking — distance (miles), steps, time (minutes)
  Reading — pages
```

- Each collection row is collapsed; click → `/collections/:id`.
- Member logs of any collection do NOT also appear in the "Logs" section
  (avoids duplication). To view a member log in isolation, the user
  clicks into the collection page first, then clicks the log name.
- An individual log page (`/logs/:id`) remains reachable and unchanged
  for standalone logs and collection members alike.

### Collection detail page (`/collections/:id`)

Three sections, top to bottom:

**Header.** Name, description (inline-editable via an Edit pencil,
same pattern as log description). An Edit button drops down to
rename/delete the collection. A small "Add logs" affordance that
opens a modal/inline picker of the user's standalone logs with
checkboxes.

**Today's practice** (combined entry form).

One row per **(log, metric)** pair. Multi-metric logs contribute
multiple rows grouped visually under the log name:

```
Sight reading (min)      [qty       ]  [note                              ]
Harmony (min)            [qty       ]  [note                              ]
Running — distance (km)  [qty       ]  [note                              ]
       — time (min)      [qty       ]  [note                              ]

                                                         [Record today]
```

Client-side rules:

- Leaving every quantity blank for a given log = skip that log (backend
  receives `quantity=0` for every metric).
- Filling any quantity for a log requires filling **all** of that log's
  metrics (same rule as the standalone multi-metric add-entry form).
  Validation error surfaces inline.
- Submit hits `POST /api/collections/:id/entries`. The response is a
  fresh `CollectionDetailResponse`; the page rerenders.

Edit and delete of existing entries happens on the individual log
page, not here. The combined form is add-only.

**Summary & history.**

```
Combined totals
  min:   Σ 60 min · avg 15 min/day · 4 days
  km:    Σ 5.2 km · avg 2.6 km/day · 2 days

Per log
  Sight reading    Total: 20 min · Avg: 10 min · Current streak: 2
  Harmony          Total:  5 min · Avg:  5 min · Current streak: 1
  Running          distance: 5.2 km · 3.5 km/day   time: 50 min · 25 min/day   Current streak: 2
  ...

History
  May 3, 2026
    Sight reading    20 min   Mozart K.545
    Harmony           5 min
    Improvisation    (skipped)
    Repertoire       45 min   Bach Sinfonia 3

  May 2, 2026
    ...
```

- **Combined totals** shows one row per unit that appears in ≥ 2
  `(log, metric)` pairs in the collection. Single-occurrence units
  don't get a combined row (no aggregation happening).
- **Per log** reuses each member's streak + per-metric stats. Log name
  is a link to the individual log page.
- **History** interleaves every member's entries by date, descending.
  Within a day, rows follow the same log-creation-order used in "Per
  log". A row showing `(skipped)` renders when every value is
  `quantity=0 && description==""`.

## Stats computation

Done client-side from the `CollectionDetailResponse`:

```elm
type alias CombinedTotal =
    { unit : String
    , total : Float
    , average : Maybe Float
    , days : Int
    , contributors : Int   -- count of (log, metric) pairs feeding this unit
    }

computeCombinedTotals : CollectionDetail -> List CombinedTotal
```

Algorithm: for each member log, for each of its metrics, emit a
`(unit, quantity, date)` triple for every entry with `quantity > 0`.
Group by unit. For each unit with `contributors >= 2`:

- `total` = sum of all quantities.
- `days` = count of distinct dates on which any contributing metric had
  `quantity > 0`.
- `average` = `total / days` if `days > 0` else `Nothing`.

## Frontend

### New files

- `frontend/src/Collection.elm` — new Elm page module for the collection
  detail view (model, msg, update, view). Follows the `LogView.elm`
  pattern.
- `frontend/tests/CombinedTotalsTests.elm` — unit tests for the
  combined-totals pure function.

### Modified files

- `frontend/src/Types.elm` — add `Collection`, `CollectionSummary`,
  `CollectionDetail`, `CombinedTotal`.
- `frontend/src/Api.elm` — new decoders/encoders; new request helpers
  `listCollections`, `getCollection`, `createCollection`, `updateCollection`,
  `deleteCollection`, `postCombinedEntry`.
- `frontend/src/Route.elm` — add `/collections/:id` route.
- `frontend/src/Main.elm` — wire the new page into the page union.
- `frontend/src/LogList.elm` — render the Collections section above the
  Logs list; add the `+ New collection` button; hide members from the
  flat Logs list.

## Backend

### New files

- `backend/src/Types/Collection.hs` — `data Collection { collId, collUserId,
  collName, collDescription, collCreatedAt, collUpdatedAt }`. The id fields
  use a new `type LogCollectionId = Text` alias added to
  `backend/src/Types/Common.hs` alongside the existing `LogId`, `UserId`,
  `EntryId` aliases.
- `backend/src/Db/Collection.hs` — hasql statements: `insertCollection`,
  `listCollectionsByUser` (returns each row plus a `memberCount` via a
  `LEFT JOIN`), `getCollection`, `updateCollection`, `deleteCollection`,
  `getCollectionMembers :: LogCollectionId -> Statement (Vector Log)`.
- `backend/src/Handler/Collections.hs` — five handlers matching the five
  collection endpoints, plus the combined-entry handler.
- `backend/dbmate/migrations/006_add_log_collections.sql` — schema above.

### Modified files

- `backend/src/Api/Types.hs` — add the collections sub-API to the top-level
  API shape.
- `backend/src/Api/RequestTypes.hs` — `CollectionResponse`,
  `CollectionSummaryResponse`, `CollectionDetailResponse`, request types
  for create/update/combined-entry.
- `backend/src/Api/Collections.hs` (new) — servant type declarations for
  the five collection endpoints.
- `backend/src/Db/Log.hs` — `updateLog` signature extended to carry
  `Maybe (Maybe LogCollectionId)` (outer Maybe = "field absent in the
  request, don't touch"; inner Maybe = "field present, may be null").
- `backend/src/Handler/Logs.hs` — `updateLogHandler` honors the new
  `collectionId` field; on assignment, verifies the collection exists
  and belongs to the same user inside the serializable update tx.
- `backend/test-api.sh` — add a collections end-to-end section (create,
  assign two logs, post combined entry, verify, delete).

## Testing

**Backend unit tests** in hspec: a pure `groupEntriesByUnit` helper if
extracted (most of the aggregation is client-side; backend unit-test
surface is small).

**Backend E2E** in `test-api.sh`:

1. Create a collection.
2. Assign two existing logs to it (via `PUT /api/logs/:id`).
3. Verify `GET /api/collections` reports `memberCount = 2`.
4. `POST /api/collections/:id/entries` for today with one log filled
   and one blank (qty=0).
5. `GET /api/collections/:id` and assert:
   - Two members with correct ids.
   - Today's entry exists for both (the real one and the skip).
   - Per-log `streakStats` are present and sane.
6. `PUT /api/logs/:id` with `{ "collectionId": null }` releases the log.
7. `DELETE /api/collections/:id`; verify remaining member is now
   `collection_id = null`.

**Frontend unit tests** for the combined-totals computation in Elm —
cases: empty collection, all single-metric shared unit, mixed units,
multi-metric log contributing to two units, everything skipped.

**Frontend decoder tests** for `CollectionResponse` /
`CollectionDetailResponse`.

## Non-goals (v1)

- Collection-level streak aggregation.
- Sharing collections between users.
- Manual reordering of logs within a collection (stable order by
  `created_at`).
- Editing or deleting past entries from the combined history view
  (per-log page owns edit/delete).
- A virtual "Uncategorized" collection for standalone logs.
- Archiving or hiding a collection.
- Moving a log into a collection during creation (create the log
  standalone first, then assign — keeps `POST /api/logs` unchanged).

## Open items for the implementation plan

- Whether the `PUT /api/logs/:id` partial-update semantics for
  `collectionId` need a marker value for "null explicitly" vs "absent"
  when the wire format is JSON. Elm's `Json.Encode` can emit
  `"collectionId": null` distinctly from omitting the key; the
  Haskell side needs to decode the two cases distinctly (a
  `Maybe (Maybe LogCollectionId)` in the request type, or a custom
  `FromJSON` instance with `explicitParseField`).
- Exact UI affordance for adding/removing logs to a collection on the
  detail page (inline picker vs. modal vs. a per-log dropdown on the
  log-edit form). The plan can pick the simplest one that meets the
  spec's intent.
- Whether the combined-entry transaction should hold a `FOR UPDATE`
  lock on each member log (as the existing single-log entry flow
  does), or a single `FOR UPDATE` on the collection row. The former
  preserves the per-log ordering invariant; the latter is simpler but
  serializes more traffic.
