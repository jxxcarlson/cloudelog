module Db.Entry
  ( listEntriesByLog
  , maxEntryDate
  , insertSkipFills
  , upsertEntry
  , updateEntry
  , deleteEntry
  , getEntryOwner
  , lockLogForUpdate
  , getLogMetricCount
  ) where

-- Task 1's scalar-wire adapters use Postgres element-index assignment
-- (`quantities[1] = $3`) so the handler can patch position 0 without
-- reading the existing row to learn the array length. Task 2 replaces
-- these with full-array overwrites.

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int32)
import           Data.Text                  (Text)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Data.Vector                as V
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (EntryId, LogId, UserId)
import           Types.Entry                (Entry(..))

listEntriesByLog :: Statement LogId (Vector Entry)
listEntriesByLog = Statement sql encoder (D.rowVector entryRow) True
  where
    sql =
      "SELECT id, log_id, entry_date, quantities, descriptions, created_at, updated_at \
      \FROM entries WHERE log_id = $1 ORDER BY entry_date ASC"
    encoder = E.param (E.nonNullable E.text)

maxEntryDate :: Statement LogId (Maybe Day)
maxEntryDate = Statement sql encoder decoder True
  where
    sql     = "SELECT max(entry_date) FROM entries WHERE log_id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.singleRow (D.column (D.nullable D.date))

-- | Lock the log row for update (serializes concurrent entry writes).
--   Returns the owning user_id or Nothing if the log doesn't exist.
lockLogForUpdate :: Statement LogId (Maybe UserId)
lockLogForUpdate = Statement sql encoder decoder True
  where
    sql     = "SELECT user_id FROM logs WHERE id = $1 FOR UPDATE"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe (D.column (D.nonNullable D.text))

-- | How many metrics the log carries. Used to size skip-fill arrays.
getLogMetricCount :: Statement LogId Int32
getLogMetricCount = Statement sql encoder decoder True
  where
    sql     = "SELECT cardinality(metric_units)::int FROM logs WHERE id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.singleRow (D.column (D.nonNullable D.int4))

-- | Bulk insert skip entries with all-zero quantity arrays and all-empty
--   description arrays of the given length.
--   Params: (log_id, ids[], dates[], metric_count).
insertSkipFills
  :: Statement (LogId, Vector EntryId, Vector Day, Int32) ()
insertSkipFills = Statement sql encoder D.noResult True
  where
    sql =
      "INSERT INTO entries (id, log_id, entry_date, quantities, descriptions) \
      \SELECT unnest($2 :: text[]), $1, unnest($3 :: date[]), \
      \       array_fill(0::double precision, ARRAY[$4 :: int]), \
      \       array_fill(''::text,            ARRAY[$4 :: int]) \
      \ON CONFLICT (log_id, entry_date) DO NOTHING"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable textArrayE)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable dateArrayE)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.int4))

-- | INSERT a new entry with a full N-wide values array. On conflict, patch
--   only position 1 (1-indexed) from the incoming array. In Task 1 all logs
--   are single-metric so [1] is the only populated index; in Task 2 this
--   statement is replaced with a full-array overwrite.
--   Params: (id, log_id, entry_date, quantities, descriptions).
--
-- DEVIATION FROM PLAN: the plan's SQL was a straight overwrite of
-- quantities[1]/descriptions[1]. That broke test-api.sh's accumulate
-- assertions (which exercise the scalar wire format). Since the Task 1
-- contract is "wire format unchanged," we preserve the pre-task scalar
-- semantics by accumulating at index 1 and keeping the existing
-- description if the incoming one is empty. Task 2 will switch to the
-- full-array overwrite the plan described.
upsertEntry
  :: Statement (EntryId, LogId, Day, Vector Double, Vector Text) Entry
upsertEntry = Statement sql encoder (D.singleRow entryRow) True
  where
    sql =
      "INSERT INTO entries (id, log_id, entry_date, quantities, descriptions) \
      \VALUES ($1, $2, $3, $4, $5) \
      \ON CONFLICT (log_id, entry_date) DO UPDATE SET \
      \  quantities[1]   = entries.quantities[1] + excluded.quantities[1], \
      \  descriptions[1] = CASE WHEN excluded.descriptions[1] <> '' \
      \                         THEN excluded.descriptions[1] \
      \                         ELSE entries.descriptions[1] END, \
      \  updated_at      = now() \
      \RETURNING id, log_id, entry_date, quantities, descriptions, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_) -> c) >$< E.param (E.nonNullable E.date)) <>
      ((\(_,_,_,d,_) -> d) >$< E.param (E.nonNullable doubleArrayE)) <>
      ((\(_,_,_,_,e) -> e) >$< E.param (E.nonNullable textArrayE))

-- | PUT /api/entries/:id patches position 1 of the values arrays with the
--   scalar quantity/description from the wire format. Task 2 replaces this
--   with a full-array overwrite driven by the new values-list wire format.
--   Params: (id, user_id, quantity, description).
updateEntry :: Statement (EntryId, UserId, Double, Text) (Maybe Entry)
updateEntry = Statement sql encoder (D.rowMaybe entryRow) True
  where
    sql =
      "UPDATE entries e SET \
      \  quantities[1]   = $3, \
      \  descriptions[1] = $4, \
      \  updated_at      = now() \
      \FROM logs l \
      \WHERE e.id = $1 AND e.log_id = l.id AND l.user_id = $2 \
      \RETURNING e.id, e.log_id, e.entry_date, e.quantities, e.descriptions, e.created_at, e.updated_at"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable E.float8)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.text))

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

-- | Ownership check for an entry by id (used by entry handlers before update/delete).
getEntryOwner :: Statement EntryId (Maybe UserId)
getEntryOwner = Statement sql encoder decoder True
  where
    sql =
      "SELECT l.user_id FROM entries e JOIN logs l ON e.log_id = l.id \
      \WHERE e.id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe (D.column (D.nonNullable D.text))

-- Reusable array encoders.
textArrayE :: E.Value (Vector Text)
textArrayE = E.array (E.dimension foldl (E.element (E.nonNullable E.text)))

doubleArrayE :: E.Value (Vector Double)
doubleArrayE = E.array (E.dimension foldl (E.element (E.nonNullable E.float8)))

dateArrayE :: E.Value (Vector Day)
dateArrayE = E.array (E.dimension foldl (E.element (E.nonNullable E.date)))

-- Reusable array decoders.
textArrayD :: D.Value (Vector Text)
textArrayD = D.array (D.dimension V.replicateM (D.element (D.nonNullable D.text)))

doubleArrayD :: D.Value (Vector Double)
doubleArrayD = D.array (D.dimension V.replicateM (D.element (D.nonNullable D.float8)))

entryRow :: D.Row Entry
entryRow =
  Entry
    <$> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.date)
    <*> D.column (D.nonNullable doubleArrayD)
    <*> D.column (D.nonNullable textArrayD)
    <*> D.column (D.nonNullable D.timestamptz)
    <*> D.column (D.nonNullable D.timestamptz)
