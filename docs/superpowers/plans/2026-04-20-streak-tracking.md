# Streak tracking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track per-log streaks (maximal runs of consecutive dates with `quantity > 0`) in a new `streaks` table, expose three aggregates (`current`, `average`, `longest`) on the log-detail response, and render a new stats row in `LogView`.

**Architecture:** Materialized table, recompute-on-write. Every entry mutation (`POST /api/logs/:id/entries`, `PUT /api/entries/:id`, `DELETE /api/entries/:id`) deletes all rows for that log and re-inserts freshly computed streaks inside the same DB transaction. Backend computes the three aggregates via a single SQL statement; the frontend consumes them directly.

**Tech Stack:** Haskell (Servant + Hasql), Postgres (dbmate migrations), Elm 0.19 frontend, hspec for backend tests, elm-test for frontend.

---

## Design reference

Source spec: `docs/superpowers/specs/2026-04-20-streak-tracking-design.md`. Key decisions baked in:

- **Streak** = maximal run of consecutive dates with `quantity > 0`. Gap or `quantity = 0` breaks it.
- **Current streak** = length of the most-recent streak row (by `start_date`). Rest-day tolerant.
- **Average** = arithmetic mean over **all** streak rows; `null` when there are none.
- **Wire format** is aggregates (`current`, `average`, `longest`), not raw streak rows.
- **`CHECK (length > 0)`** — zero-length streaks aren't stored.
- **Integer PK** (`SERIAL`) for `streaks.id`. Rows are transient (deleted & reinserted on every entry write) and never referenced externally, so the existing externally-generated-UUID pattern buys nothing here.

---

## File map

**Create:**
- `backend/dbmate/migrations/003_add_streaks.sql` — table + one-shot backfill.
- `backend/src/Service/Streak.hs` — pure streak computation.
- `backend/src/Db/Streak.hs` — hasql statements.
- `backend/test/Service/StreakSpec.hs` — hspec unit tests.
- `frontend/tests/StreakStatsDecoderTests.elm` — decoder test.

**Modify:**
- `backend/cloudelog-backend.cabal` — register new modules.
- `backend/test/Spec.hs` — wire new spec into runner.
- `backend/src/Api/RequestTypes.hs` — add `StreakStats` + `ldrStreakStats`.
- `backend/src/Db/Entry.hs` — `deleteEntry` returns log_id instead of row count.
- `backend/src/Handler/Entries.hs` — three handlers call `recomputeStreaksTx` inside a transaction.
- `backend/src/Handler/Logs.hs` — `getLogHandler` loads streak stats; export `recomputeStreaksTx` (or put it in `Db.Streak`).
- `backend/test-api.sh` — e2e assertions on `streakStats`.
- `frontend/src/Types.elm` — `StreakStats` alias.
- `frontend/src/Api.elm` — decoder + `getLog` returns streak stats.
- `frontend/src/LogView.elm` — new row below `Days | Skipped | Total | Avg`.
- `frontend/src/Main.elm` — wire getLog result into LogView model.
- `db/schema.sql` — re-dump after migration.

---

## Task 1: Create the `streaks` table with backfill

**Files:**
- Create: `backend/dbmate/migrations/003_add_streaks.sql`
- Modify: `db/schema.sql` (regenerated after migration)

- [ ] **Step 1: Write the migration**

Create `backend/dbmate/migrations/003_add_streaks.sql`:

```sql
-- migrate:up

CREATE TABLE streaks (
    id          SERIAL PRIMARY KEY,
    log_id      TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
    start_date  DATE NOT NULL,
    length      INTEGER NOT NULL CHECK (length > 0),
    UNIQUE (log_id, start_date)
);

CREATE INDEX streaks_log_idx ON streaks (log_id);

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

DROP INDEX IF EXISTS streaks_log_idx;
DROP TABLE IF EXISTS streaks;
```

- [ ] **Step 2: Apply the migration**

Run from the repo root:
```
./run migrate up
```
Expected: dbmate reports `003_add_streaks.sql` applied, no errors.

- [ ] **Step 3: Spot-check the backfill**

```
psql cloudelog_dev -c "SELECT log_id, start_date, length FROM streaks ORDER BY log_id, start_date LIMIT 20;"
```
Expected: one row per maximal run of `quantity > 0` entries. For a log with entries on 4/1, 4/2, 4/3 (all qty > 0) and 4/4 (qty=0), expect one row with `start_date = 4/1, length = 3`.

- [ ] **Step 4: Regenerate `db/schema.sql`**

```
./run schema dump
```
(or whichever script the repo already uses — check `scripts/` for the existing dump flow). Expected: `db/schema.sql` gains the `streaks` table definition.

- [ ] **Step 5: Commit**

```
git add backend/dbmate/migrations/003_add_streaks.sql db/schema.sql
git commit -m "db: add streaks table with backfill from existing entries"
```

---

## Task 2: Pure streak computation (`Service.Streak`) + unit tests

**Files:**
- Create: `backend/src/Service/Streak.hs`
- Create: `backend/test/Service/StreakSpec.hs`
- Modify: `backend/cloudelog-backend.cabal`
- Modify: `backend/test/Spec.hs`

- [ ] **Step 1: Add module to cabal library and test-suite**

In `backend/cloudelog-backend.cabal`, library `exposed-modules`, add `Service.Streak` (alphabetically, near `Service.SkipFill`). In test-suite `other-modules`, add `Service.StreakSpec` (near `Service.SkipFillSpec`).

- [ ] **Step 2: Write the failing spec**

Create `backend/test/Service/StreakSpec.hs`:

```haskell
module Service.StreakSpec (spec) where

import           Data.Time.Calendar (fromGregorian)
import qualified Service.Streak     as Streak
import           Test.Hspec

spec :: Spec
spec = describe "Service.Streak.computeStreaks" $ do

  it "empty list: no streaks" $
    Streak.computeStreaks [] `shouldBe` []

  it "all-zero entries: no streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 0)
      , (fromGregorian 2026 4 2, 0)
      , (fromGregorian 2026 4 3, 0)
      ] `shouldBe` []

  it "single qty>0 entry: one streak of length 1" $
    Streak.computeStreaks [(fromGregorian 2026 4 1, 3.5)]
      `shouldBe` [(fromGregorian 2026 4 1, 1)]

  it "uninterrupted 5-day run: one streak of length 5" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 3, 1)
      , (fromGregorian 2026 4 4, 1)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe` [(fromGregorian 2026 4 1, 5)]

  it "run broken by quantity=0: two streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 3, 0)
      , (fromGregorian 2026 4 4, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 2)
        , (fromGregorian 2026 4 4, 1)
        ]

  it "run with a calendar gap (missing date): two streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 2)
        , (fromGregorian 2026 4 5, 1)
        ]

  it "alternating qty>0 / qty=0: many length-1 streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 0)
      , (fromGregorian 2026 4 3, 1)
      , (fromGregorian 2026 4 4, 0)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 1)
        , (fromGregorian 2026 4 3, 1)
        , (fromGregorian 2026 4 5, 1)
        ]

  it "negative quantity: treated like zero (breaks the streak)" $
    -- Guards against accidental regressions if handler validation ever misses a negative.
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, -1)
      , (fromGregorian 2026 4 3, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 1)
        , (fromGregorian 2026 4 3, 1)
        ]
```

Wire it into the runner — `backend/test/Spec.hs`:

```haskell
module Main where

import           Test.Hspec
import qualified Service.SkipFillSpec
import qualified Service.StreakSpec

main :: IO ()
main = hspec $ do
  describe "Service.SkipFill" Service.SkipFillSpec.spec
  describe "Service.Streak"   Service.StreakSpec.spec
```

- [ ] **Step 3: Run the suite and confirm failure**

```
cd backend && stack test
```
Expected: compilation failure — `Service.Streak` does not exist yet.

- [ ] **Step 4: Implement `Service.Streak`**

Create `backend/src/Service/Streak.hs`:

```haskell
module Service.Streak (computeStreaks) where

import Data.Time.Calendar (Day, addDays)

-- | Given entries sorted by date ascending, produce one (start_date, length) tuple
--   per maximal run of consecutive dates with quantity > 0. A calendar gap or
--   a quantity <= 0 breaks the run.
computeStreaks :: [(Day, Double)] -> [(Day, Int)]
computeStreaks = go Nothing []
  where
    -- State: `cur` = Just (start, length) of the in-progress run, or Nothing.
    --        `acc` = finalized runs in reverse order.
    go :: Maybe (Day, Int) -> [(Day, Int)] -> [(Day, Double)] -> [(Day, Int)]
    go cur acc [] = reverse (maybe acc (: acc) cur)
    go cur acc ((d, q) : rest)
      | q > 0 = case cur of
          Nothing          -> go (Just (d, 1)) acc rest
          Just (s, n)
            | addDays (fromIntegral n) s == d -> go (Just (s, n + 1)) acc rest
            | otherwise                       -> go (Just (d, 1))     (flush cur acc) rest
      | otherwise = go Nothing (flush cur acc) rest

    flush Nothing  acc = acc
    flush (Just r) acc = r : acc
```

- [ ] **Step 5: Run the suite and confirm pass**

```
cd backend && stack test
```
Expected: all `Service.Streak.computeStreaks` specs pass; all other specs still pass.

- [ ] **Step 6: Commit**

```
git add backend/src/Service/Streak.hs backend/test/Service/StreakSpec.hs \
        backend/test/Spec.hs backend/cloudelog-backend.cabal
git commit -m "backend: pure streak computation with hspec coverage"
```

---

## Task 3: `Db.Streak` — hasql statements

**Files:**
- Create: `backend/src/Db/Streak.hs`
- Modify: `backend/cloudelog-backend.cabal`

- [ ] **Step 1: Register the module**

In `backend/cloudelog-backend.cabal` library `exposed-modules`, add `Db.Streak` (alphabetically near `Db.Entry`, `Db.Log`).

- [ ] **Step 2: Implement the module**

Create `backend/src/Db/Streak.hs`:

```haskell
module Db.Streak
  ( selectEntryDateQuantity
  , deleteStreaksForLog
  , bulkInsertStreaks
  , selectStreakStats
  , StreakStatsRow(..)
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int32)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (LogId)

-- | All entries for a log, returned as (entry_date, quantity) in ascending date order.
--   Feeds Service.Streak.computeStreaks.
selectEntryDateQuantity :: Statement LogId (Vector (Day, Double))
selectEntryDateQuantity = Statement sql encoder decoder True
  where
    sql =
      "SELECT entry_date, quantity FROM entries \
      \WHERE log_id = $1 ORDER BY entry_date ASC"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowVector $
      (,) <$> D.column (D.nonNullable D.date)
          <*> D.column (D.nonNullable D.float8)

deleteStreaksForLog :: Statement LogId ()
deleteStreaksForLog = Statement sql encoder D.noResult True
  where
    sql     = "DELETE FROM streaks WHERE log_id = $1"
    encoder = E.param (E.nonNullable E.text)

-- | Bulk insert streaks. Params: (log_id, start_dates[], lengths[]).
--   The two arrays are paired element-wise via unnest.
bulkInsertStreaks :: Statement (LogId, Vector Day, Vector Int32) ()
bulkInsertStreaks = Statement sql encoder D.noResult True
  where
    sql =
      "INSERT INTO streaks (log_id, start_date, length) \
      \SELECT $1, unnest($2 :: date[]), unnest($3 :: int[])"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.date)))))) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.int4))))))

-- | Three streak aggregates in one round-trip.
--   current = length of the most-recent streak (by start_date), 0 if none.
--   average = arithmetic mean of all streak lengths, NULL if none.
--   longest = max streak length, 0 if none.
data StreakStatsRow = StreakStatsRow
  { ssrCurrent :: Int32
  , ssrAverage :: Maybe Double
  , ssrLongest :: Int32
  } deriving (Show, Eq)

selectStreakStats :: Statement LogId StreakStatsRow
selectStreakStats = Statement sql encoder decoder True
  where
    sql =
      "SELECT \
      \  COALESCE((SELECT length FROM streaks WHERE log_id = $1 \
      \            ORDER BY start_date DESC LIMIT 1), 0)        AS current_, \
      \  (SELECT AVG(length)::double precision FROM streaks \
      \   WHERE log_id = $1)                                    AS avg_, \
      \  COALESCE((SELECT MAX(length) FROM streaks WHERE log_id = $1), 0) AS longest_"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.singleRow $
      StreakStatsRow
        <$> D.column (D.nonNullable D.int4)
        <*> D.column (D.nullable    D.float8)
        <*> D.column (D.nonNullable D.int4)
```

- [ ] **Step 3: Compile-check**

```
cd backend && stack build
```
Expected: no errors. No new tests yet — these are thin DB wrappers covered by the e2e test in Task 6.

- [ ] **Step 4: Commit**

```
git add backend/src/Db/Streak.hs backend/cloudelog-backend.cabal
git commit -m "backend: Db.Streak hasql statements for streak CRUD"
```

---

## Task 4: `recomputeStreaksTx` helper + wire into entry handlers

**Files:**
- Modify: `backend/src/Db/Entry.hs` (change `deleteEntry` to return `Maybe LogId`)
- Modify: `backend/src/Handler/Entries.hs` (all three handlers)

- [ ] **Step 1: Change `deleteEntry` to return the deleted entry's log_id**

In `backend/src/Db/Entry.hs`, replace the `deleteEntry` definition with:

```haskell
-- | Delete an entry by id scoped to owner. Returns the deleted entry's log_id,
--   or Nothing if nothing was deleted (not found or not owned).
deleteEntry :: Statement (EntryId, UserId) (Maybe LogId)
deleteEntry = Statement sql encoder decoder True
  where
    sql =
      "DELETE FROM entries WHERE id = $1 AND log_id IN \
      \  (SELECT id FROM logs WHERE user_id = $2) \
      \RETURNING log_id"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))
    decoder = D.rowMaybe (D.column (D.nonNullable D.text))
```

Also remove the now-unused import `Data.Int (Int64)` if no other statement still needs it.

- [ ] **Step 2: Add `recomputeStreaksTx` helper in `Handler.Entries`**

Open `backend/src/Handler/Entries.hs`. Add imports:

```haskell
import qualified Data.Vector             as V
import qualified Db.Streak               as DbStreak
import qualified Service.Streak          as Streak
import           Data.Int                (Int32)
import           Types.Common            (LogId)
```

(Some of these may already be imported; dedupe as needed.)

Add near the bottom of the module, above the `validateQuantity` helper:

```haskell
-- | Recompute and persist streaks for @lid@. Call inside the same transaction
--   as any entry mutation so the streaks table stays in lockstep with entries.
recomputeStreaksTx :: LogId -> Tx.Transaction ()
recomputeStreaksTx lid = do
  pairs <- V.toList <$> Tx.statement lid DbStreak.selectEntryDateQuantity
  let streaks    = Streak.computeStreaks pairs
      dates      = V.fromList (map fst streaks)
      lengths    = V.fromList (map (fromIntegral . snd :: Int -> Int32) streaks)
  Tx.statement lid DbStreak.deleteStreaksForLog
  if V.null dates
    then pure ()
    else Tx.statement (lid, dates, lengths) DbStreak.bulkInsertStreaks
```

- [ ] **Step 3: Call `recomputeStreaksTx` from `postEntryHandler`**

In the transaction body of `postEntryHandler`, after the existing `allEntries <- Tx.statement lid DbEntry.listEntriesByLog` line and before `pure (Right allEntries)`, insert:

```haskell
              recomputeStreaksTx lid
```

Final shape of that branch:

```haskell
              _ <- if null preFillDays
                     then pure ()
                     else Tx.statement (lid, V.fromList preFillIds, V.fromList preFillDays)
                                       DbEntry.insertSkipFills
              _entry <- Tx.statement
                          (newEntryId, lid, cerEntryDate, cerQuantity, desc)
                          DbEntry.upsertEntry
              recomputeStreaksTx lid
              allEntries <- Tx.statement lid DbEntry.listEntriesByLog
              pure (Right allEntries)
```

- [ ] **Step 4: Convert `updateEntryHandler` to a transaction and recompute**

Replace the body of `updateEntryHandler` with:

```haskell
updateEntryHandler :: AuthResult AuthUser -> Text -> UpdateEntryRequest -> AppM EntryResponse
updateEntryHandler auth eid UpdateEntryRequest{..} = do
  uid <- requireUser auth
  validateQuantity uerQuantity
  pool <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mE <- Tx.statement (eid, uid, uerQuantity, uerDescription) DbEntry.updateEntry
      case mE of
        Nothing -> pure Nothing
        Just e  -> do
          recomputeStreaksTx (entLogId e)
          pure (Just e)
  case result of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just e) -> pure (toEntryResponse e)
```

Add the import `import Types.Entry (Entry(..))` if not already present.

- [ ] **Step 5: Convert `deleteEntryHandler` to a transaction and recompute**

Replace the body of `deleteEntryHandler` with:

```haskell
deleteEntryHandler :: AuthResult AuthUser -> Text -> AppM NoContent
deleteEntryHandler auth eid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mLid <- Tx.statement (eid, uid) DbEntry.deleteEntry
      case mLid of
        Nothing  -> pure Nothing
        Just lid -> do
          recomputeStreaksTx lid
          pure (Just ())
  case result of
    Left _        -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing -> throwError $ appErrorToServantErr NotFound
    Right _       -> pure NoContent
```

- [ ] **Step 6: Build and fix compile errors**

```
cd backend && stack build 2>&1 | tail -40
```
Expected: clean build.

- [ ] **Step 7: Run unit tests to confirm nothing regressed**

```
cd backend && stack test
```
Expected: all green.

- [ ] **Step 8: Commit**

```
git add backend/src/Db/Entry.hs backend/src/Handler/Entries.hs
git commit -m "backend: recompute streaks in-tx on every entry mutation"
```

---

## Task 5: `StreakStats` response type + wire into `getLogHandler`

**Files:**
- Modify: `backend/src/Api/RequestTypes.hs`
- Modify: `backend/src/Handler/Logs.hs`

- [ ] **Step 1: Add `StreakStats` and extend `LogDetailResponse`**

In `backend/src/Api/RequestTypes.hs`, after the `LogDetailResponse` definition, add:

```haskell
data StreakStats = StreakStats
  { ssCurrent :: Int
  , ssAverage :: Maybe Double
  , ssLongest :: Int
  } deriving (Show, Generic)
instance ToJSON StreakStats where toJSON = genericToJSON (stripPrefixOptions 2)
```

Replace the existing `LogDetailResponse` with:

```haskell
data LogDetailResponse = LogDetailResponse
  { ldrLog         :: LogResponse
  , ldrEntries     :: [EntryResponse]
  , ldrStreakStats :: StreakStats
  } deriving (Show, Generic)
instance ToJSON LogDetailResponse where toJSON = genericToJSON (stripPrefixOptions 3)
```

The existing `stripPrefixOptions 3` for `LogDetailResponse` keeps `log`, `entries`, `streakStats` as the wire names (drops the `ldr` prefix, lowercases first char).

- [ ] **Step 2: Load streak stats in `getLogHandler`**

In `backend/src/Handler/Logs.hs`, add imports:

```haskell
import qualified Db.Streak               as DbStreak
import           Data.Int                (Int32)
```

Replace the `getLogHandler` body (the `Right (Just l)` branch) so that just before the final `pure LogDetailResponse { ... }`, it also loads the stats. Full rewrite of the function:

```haskell
getLogHandler :: AuthResult AuthUser -> Text -> AppM LogDetailResponse
getLogHandler auth lid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  rLog <- liftIO $ Pool.use pool $ Session.statement (lid, uid) DbLog.getLog
  case rLog of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just l) -> do
      rEntries <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.listEntriesByLog
      entries <- case rEntries of
        Left _  -> throwError $ appErrorToServantErr (Internal "database error")
        Right v -> pure (V.toList v)
      rStats <- liftIO $ Pool.use pool $ Session.statement lid DbStreak.selectStreakStats
      stats <- case rStats of
        Left _  -> throwError $ appErrorToServantErr (Internal "database error")
        Right s -> pure s
      -- Fire-and-forget: update current_log_id. Don't fail the request on error.
      _ <- liftIO $ Pool.use pool $ Session.statement (uid, lid) DbUser.setCurrentLogId
      pure LogDetailResponse
        { ldrLog         = toLogResponse l
        , ldrEntries     = map toEntryResponse entries
        , ldrStreakStats = toStreakStats stats
        }
  where
    toStreakStats :: DbStreak.StreakStatsRow -> StreakStats
    toStreakStats DbStreak.StreakStatsRow{..} = StreakStats
      { ssCurrent = fromIntegral ssrCurrent
      , ssAverage = ssrAverage
      , ssLongest = fromIntegral ssrLongest
      }
```

- [ ] **Step 3: Build**

```
cd backend && stack build 2>&1 | tail -30
```
Expected: clean build.

- [ ] **Step 4: Manual smoke test**

Start the backend dev server (`./run restart backend` or equivalent), then:

```
curl -s -b /tmp/cookies 'http://localhost:8081/api/logs/<some-log-id>' | python3 -m json.tool | head -20
```
Expected: the JSON includes `"streakStats": {"current": ..., "average": ..., "longest": ...}`.

If you don't have an existing log, skip — the e2e test in Task 6 will exercise this end-to-end.

- [ ] **Step 5: Commit**

```
git add backend/src/Api/RequestTypes.hs backend/src/Handler/Logs.hs
git commit -m "backend: expose streakStats on LogDetailResponse"
```

---

## Task 6: End-to-end tests in `test-api.sh`

**Files:**
- Modify: `backend/test-api.sh`

- [ ] **Step 1: Append a streak-stats section at the end of the script**

Append to `backend/test-api.sh`, before the final success line:

```bash
say "Streak tracking"

# Fresh log starting today.
LOG_S=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Streaks","unit":"minutes","description":""}')
LOG_S_ID=$(echo "$LOG_S" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

post_entry() {
  local date="$1" qty="$2"
  curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_S_ID/entries" \
    -H "Content-Type: application/json" \
    -d "{\"entryDate\":\"$date\",\"quantity\":$qty,\"description\":\"\"}" \
    > /dev/null
}

get_stats() {
  curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_S_ID" \
    | python3 -c '
import sys, json
s = json.load(sys.stdin)["streakStats"]
avg = "null" if s["average"] is None else f"{float(s[\"average\"]):.1f}"
print(f"{s[\"current\"]}|{avg}|{s[\"longest\"]}")
'
}

# macOS/Linux date helpers already defined earlier in the script; compute 5 days worth.
if date -u -v-4d +%Y-%m-%d >/dev/null 2>&1; then
  D0=$(date -u -v-4d +%Y-%m-%d)
  D1=$(date -u -v-3d +%Y-%m-%d)
  D2=$(date -u -v-2d +%Y-%m-%d)
  D3=$(date -u -v-1d +%Y-%m-%d)
  D4=$TODAY
else
  D0=$(date -u -d '4 days ago' +%Y-%m-%d)
  D1=$(date -u -d '3 days ago' +%Y-%m-%d)
  D2=$(date -u -d '2 days ago' +%Y-%m-%d)
  D3=$(date -u -d '1 day ago'  +%Y-%m-%d)
  D4=$TODAY
fi

# Three consecutive qty>0 entries: D0, D1, D2.
post_entry "$D0" 5
post_entry "$D1" 5
post_entry "$D2" 5

STATS=$(get_stats)
[ "$STATS" = "3|3.0|3" ] && ok "three-day streak: current=3, avg=3, longest=3" \
  || fail "expected 3|3.0|3, got $STATS"

# Post a skip (qty=0) for D3 — most-recent streak length should still read 3
# (rest-day tolerant: "current" = length of most recent streak, not 0).
post_entry "$D3" 0

STATS=$(get_stats)
[ "$STATS" = "3|3.0|3" ] && ok "skip day keeps current=3 (rest-day tolerant)" \
  || fail "expected 3|3.0|3 after skip, got $STATS"

# Post qty>0 for D4 — a new 1-day streak starts.
post_entry "$D4" 5

STATS=$(get_stats)
[ "$STATS" = "1|2.0|3" ] && ok "after new entry: current=1, avg=2, longest=3" \
  || fail "expected 1|2.0|3, got $STATS"

# Update D3 (the skip) to qty>0 — streaks merge into a single 5-day run.
D3_ID=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_S_ID" \
  | python3 -c "import sys,json; es=json.load(sys.stdin)['entries']; print(next(e for e in es if e['entryDate']=='$D3')['id'])")
curl -sS -b "$COOKIES" -X PUT "$BASE/api/entries/$D3_ID" \
  -H "Content-Type: application/json" \
  -d '{"quantity":5,"description":""}' > /dev/null

STATS=$(get_stats)
[ "$STATS" = "5|5.0|5" ] && ok "update skip→qty>0 merges streaks: 5|5.0|5" \
  || fail "expected 5|5.0|5, got $STATS"

# Empty log: a log with no qty>0 entries has current=0, avg=null, longest=0.
LOG_E=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Empty","unit":"minutes","description":""}')
LOG_E_ID=$(echo "$LOG_E" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
EMPTY=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_E_ID" \
  | python3 -c '
import sys, json
s = json.load(sys.stdin)["streakStats"]
avg = "null" if s["average"] is None else f"{float(s[\"average\"]):.1f}"
print(f"{s[\"current\"]}|{avg}|{s[\"longest\"]}")
')
[ "$EMPTY" = "0|null|0" ] && ok "empty log: 0|null|0" \
  || fail "expected 0|null|0, got $EMPTY"
```

(Python prints `None` for a JSON `null`, so the expected string compares `None`.)

- [ ] **Step 2: Run the full e2e suite**

Make sure the backend is running at `$BASE` (defaults to localhost:8081). Then:

```
bash backend/test-api.sh
```
Expected: every section — including the new "Streak tracking" section — prints `✓` lines and the script exits 0.

- [ ] **Step 3: Commit**

```
git add backend/test-api.sh
git commit -m "test-api: e2e coverage for streakStats on create/update/delete"
```

---

## Task 7: Frontend types + decoders

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Api.elm`
- Create: `frontend/tests/StreakStatsDecoderTests.elm`

- [ ] **Step 1: Add `StreakStats` type alias**

In `frontend/src/Types.elm`, add (near the other record aliases):

```elm
type alias StreakStats =
    { current : Int
    , average : Maybe Float
    , longest : Int
    }
```

Export it from the module header (add `StreakStats` to the `exposing (...)` list).

- [ ] **Step 2: Write a failing decoder test**

Create `frontend/tests/StreakStatsDecoderTests.elm`:

```elm
module StreakStatsDecoderTests exposing (suite)

import Api
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "streakStatsDecoder"
        [ test "decodes a populated streakStats object" <|
            \_ ->
                let
                    json =
                        """{ "current": 3, "average": 2.5, "longest": 7 }"""
                in
                case D.decodeString Api.streakStatsDecoder json of
                    Ok ss ->
                        Expect.all
                            [ \s -> Expect.equal 3 s.current
                            , \s -> Expect.equal (Just 2.5) s.average
                            , \s -> Expect.equal 7 s.longest
                            ]
                            ss

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "decodes null average as Nothing" <|
            \_ ->
                let
                    json =
                        """{ "current": 0, "average": null, "longest": 0 }"""
                in
                case D.decodeString Api.streakStatsDecoder json of
                    Ok ss ->
                        Expect.equal Nothing ss.average

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
```

- [ ] **Step 3: Run elm-test and confirm failure**

```
cd frontend && npx elm-test tests/StreakStatsDecoderTests.elm
```
Expected: compilation failure — `Api.streakStatsDecoder` does not exist.

- [ ] **Step 4: Export the decoder and change `getLog` to carry `streakStats`**

In `frontend/src/Api.elm`:

1. Add `streakStatsDecoder` to the `module Api exposing (...)` list, and add `StreakStats` to the `Types` import.

   Change:
   ```elm
   import Types exposing (Entry, Log, LogSummary, Unit(..), User, unitFromString, unitToString)
   ```
   to:
   ```elm
   import Types exposing (Entry, Log, LogSummary, StreakStats, Unit(..), User, unitFromString, unitToString)
   ```

2. Add the decoder (place it near `entryDecoder`):

   ```elm
   streakStatsDecoder : D.Decoder StreakStats
   streakStatsDecoder =
       D.map3 StreakStats
           (D.field "current" D.int)
           (D.field "average" (D.nullable D.float))
           (D.field "longest" D.int)
   ```

3. Change `getLog` to also decode `streakStats`:

   ```elm
   getLog :
       String
       -> (Result Http.Error { log : Log, entries : List Entry, streakStats : StreakStats } -> msg)
       -> Cmd msg
   getLog logId toMsg =
       cookieRequest
           { method = "GET"
           , url = apiBase ++ "/api/logs/" ++ logId
           , body = Http.emptyBody
           , expect =
               Http.expectJson toMsg
                   (D.map3 (\l es ss -> { log = l, entries = es, streakStats = ss })
                       (D.field "log" logDecoder)
                       (D.field "entries" (D.list entryDecoder))
                       (D.field "streakStats" streakStatsDecoder)
                   )
           }
   ```

- [ ] **Step 5: Run elm-test, confirm pass**

```
cd frontend && npx elm-test
```
Expected: all suites pass.

- [ ] **Step 6: Commit**

```
git add frontend/src/Types.elm frontend/src/Api.elm \
        frontend/tests/StreakStatsDecoderTests.elm
git commit -m "frontend: StreakStats type and decoder, getLog carries it through"
```

---

## Task 8: Render the new stats row in `LogView`

**Files:**
- Modify: `frontend/src/LogView.elm`

`Main.elm` does not reference `Api.getLog` or `LogFetched` — it only wires `LogView.init/update/view` through its page union — so no `Main.elm` change is needed.

- [ ] **Step 1: Add `streakStats` to `LogView.Model` and wire the updated `getLog` payload**

In `frontend/src/LogView.elm`:

1. Extend the `Types` import at line 9:

   Change:
   ```elm
   import Types exposing (Entry, Log, Unit(..), unitToString)
   ```
   to:
   ```elm
   import Types exposing (Entry, Log, StreakStats, Unit(..), unitToString)
   ```

2. Add to the `Model` record (after `entries : List Entry` at line 80):
   ```elm
       , streakStats : Maybe StreakStats
   ```

3. Initialize it in `init` (insert alongside the other `= Nothing` defaults around line 99–104):
   ```elm
       , streakStats = Nothing
   ```

4. Change the `LogFetched` constructor at line 110 so its payload carries the extra field:

   Replace:
   ```elm
       = LogFetched (Result Http.Error { log : Log, entries : List Entry })
   ```
   with:
   ```elm
       = LogFetched (Result Http.Error { log : Log, entries : List Entry, streakStats : StreakStats })
   ```

5. Update the `Ok` branch at line 137 to destructure and store the new field:

   Replace:
   ```elm
           LogFetched (Ok { log, entries }) ->
               ( { model | log = Just log, entries = entries, loading = False, error = Nothing }
               , Cmd.none
               , NoOp
               )
   ```
   with:
   ```elm
           LogFetched (Ok { log, entries, streakStats }) ->
               ( { model
                   | log = Just log
                   , entries = entries
                   , streakStats = Just streakStats
                   , loading = False
                   , error = Nothing
                 }
               , Cmd.none
               , NoOp
               )
   ```

   Leave the `Err` branch unchanged.

- [ ] **Step 2: Add the view helper**

Add next to `viewStats` in `LogView.elm`:

```elm
viewStreakStats : Maybe StreakStats -> Html msg
viewStreakStats mss =
    let
        dash =
            "—"

        intCell label n =
            div []
                [ text
                    (label
                        ++ ": "
                        ++ (if n <= 0 then
                                dash

                            else
                                String.fromInt n
                           )
                    )
                ]

        avgCell label ma =
            div []
                [ text
                    (label
                        ++ ": "
                        ++ (case ma of
                                Just a ->
                                    -- one decimal place, matches Avg in viewStats
                                    let
                                        rounded =
                                            toFloat (round (a * 10)) / 10
                                    in
                                    String.fromFloat rounded

                                Nothing ->
                                    dash
                           )
                    )
                ]
    in
    case mss of
        Nothing ->
            text ""

        Just ss ->
            div [ class "stats" ]
                [ intCell "Current streak" ss.current
                , avgCell "Avg streak" ss.average
                , intCell "Longest streak" ss.longest
                ]
```

- [ ] **Step 3: Render it in the view**

In the `view` function, directly after the existing `viewStats stats` call (`LogView.elm:340`), insert:

```elm
                , viewStreakStats model.streakStats
```

so the final sequence reads:

```elm
                , viewStats stats
                , viewStreakStats model.streakStats
                , viewDescription model.editingDesc log
```

- [ ] **Step 4: Build the frontend**

```
cd frontend && elm make src/Main.elm --output=/tmp/cloudelog-main.js
```
Expected: clean compile, zero warnings about unused code from new symbols.

- [ ] **Step 5: Run frontend tests**

```
cd frontend && npx elm-test
```
Expected: all suites pass (including the new decoder test and the existing `ComputeStatsTests`, which `Stats` wasn't touched).

- [ ] **Step 6: Visual check in the dev browser**

Start the dev stack (backend + `serve.py` on `:8011`), sign in, open a log with a few entries mixing `quantity > 0` and `quantity = 0`. Confirm:

- The new row "Current streak | Avg streak | Longest streak" appears directly below "Days | Skipped | Total | Avg".
- Numbers match expectations (a log with `[5, 5, 5, 0, 5]` across 5 consecutive days shows `current=1, avg=2.0, longest=3`).
- An empty log (no qty>0 yet) shows all dashes.

If the UI looks wrong, capture the discrepancy and fix before committing.

- [ ] **Step 7: Commit**

```
git add frontend/src/LogView.elm
git commit -m "frontend: render Current/Avg/Longest streak row in LogView"
```

---

## Verification checklist (run after all tasks)

- [ ] `cd backend && stack build && stack test` → green.
- [ ] Backend running locally; `bash backend/test-api.sh` → green end-to-end, including the "Streak tracking" section.
- [ ] `cd frontend && npx elm-test` → green.
- [ ] `cd frontend && elm make src/Main.elm --optimize --output=elm.js` → no warnings.
- [ ] Manual browser smoke: log-view page shows the new row; behavior matches the rest-day-tolerant "current streak" decision.
- [ ] `git log --oneline` shows one commit per task (Task 1–8) — no squashed or skipped commits.
