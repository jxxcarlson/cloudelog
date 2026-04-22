module Db.Entry
  ( listEntriesByLog
  , maxEntryDate
  , insertSkipFills
  , upsertEntry
  , updateEntry
  , deleteEntry
  , selectEntryForOwner
  , lockLogForUpdate
  , getLogMetricCount
  ) where

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

-- | INSERT a new entry with a full values array. On conflict, accumulate
--   quantities elementwise and append descriptions elementwise with a
--   single space separator (empty-slot wins preserve the other side
--   verbatim).
upsertEntry
  :: Statement (EntryId, LogId, Day, Vector Double, Vector Text) Entry
upsertEntry = Statement sql encoder (D.singleRow entryRow) True
  where
    sql =
      "INSERT INTO entries (id, log_id, entry_date, quantities, descriptions) \
      \VALUES ($1, $2, $3, $4, $5) \
      \ON CONFLICT (log_id, entry_date) DO UPDATE SET \
      \  quantities   = ARRAY( \
      \    SELECT q + r \
      \    FROM unnest(entries.quantities, excluded.quantities) AS t(q, r) \
      \  ), \
      \  descriptions = ARRAY( \
      \    SELECT CASE \
      \             WHEN e = '' THEN x \
      \             WHEN x = '' THEN e \
      \             ELSE e || ' ' || x \
      \           END \
      \    FROM unnest(entries.descriptions, excluded.descriptions) AS t(e, x) \
      \  ), \
      \  updated_at   = now() \
      \RETURNING id, log_id, entry_date, quantities, descriptions, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_) -> c) >$< E.param (E.nonNullable E.date)) <>
      ((\(_,_,_,d,_) -> d) >$< E.param (E.nonNullable doubleArrayE)) <>
      ((\(_,_,_,_,e) -> e) >$< E.param (E.nonNullable textArrayE))

-- | PUT /api/entries/:id overwrites the entire quantities and descriptions arrays.
--   Params: (id, user_id, quantities, descriptions).
updateEntry
  :: Statement (EntryId, UserId, Vector Double, Vector Text) (Maybe Entry)
updateEntry = Statement sql encoder (D.rowMaybe entryRow) True
  where
    sql =
      "UPDATE entries e SET quantities = $3, descriptions = $4, updated_at = now() \
      \FROM logs l \
      \WHERE e.id = $1 AND e.log_id = l.id AND l.user_id = $2 \
      \RETURNING e.id, e.log_id, e.entry_date, e.quantities, e.descriptions, e.created_at, e.updated_at"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable doubleArrayE)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable textArrayE))

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

-- | Select the entry scoped to its owner. Returns Nothing if missing or not
--   owned by the given user. Used by updateEntryHandler to read the current
--   array length so it can enforce the wire-format length check.
selectEntryForOwner :: Statement (EntryId, UserId) (Maybe Entry)
selectEntryForOwner = Statement sql encoder (D.rowMaybe entryRow) True
  where
    sql =
      "SELECT e.id, e.log_id, e.entry_date, e.quantities, e.descriptions, e.created_at, e.updated_at \
      \FROM entries e JOIN logs l ON e.log_id = l.id \
      \WHERE e.id = $1 AND l.user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

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
