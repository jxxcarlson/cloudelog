module Db.Entry
  ( listEntriesByLog
  , maxEntryDate
  , insertSkipFills
  , upsertEntry
  , updateEntry
  , deleteEntry
  , getEntryOwner
  , lockLogForUpdate
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int64)
import           Data.Text                  (Text)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (EntryId, LogId, UserId)
import           Types.Entry                (Entry(..))

listEntriesByLog :: Statement LogId (Vector Entry)
listEntriesByLog = Statement sql encoder (D.rowVector entryRow) True
  where
    sql =
      "SELECT id, log_id, entry_date, quantity, description, created_at, updated_at \
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

-- | Bulk insert skip entries (quantity = 0). Each element is a (id, date) pair.
--   Uses `unnest` with parameter arrays for an efficient single-round-trip insert.
--   `ON CONFLICT DO NOTHING` so concurrent inserts are idempotent.
insertSkipFills :: Statement (LogId, Vector EntryId, Vector Day) ()
insertSkipFills = Statement sql encoder D.noResult True
  where
    sql =
      "INSERT INTO entries (id, log_id, entry_date, quantity, description) \
      \SELECT unnest($2 :: text[]), $1, unnest($3 :: date[]), 0, '' \
      \ON CONFLICT (log_id, entry_date) DO NOTHING"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.text)))))) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.date))))))

-- | Insert or accumulate on (log_id, entry_date). Implements Q6:
--   quantity sums; description overwrites only if new one is non-empty.
--   Params: (id, log_id, entry_date, quantity, description).
upsertEntry :: Statement (EntryId, LogId, Day, Double, Text) Entry
upsertEntry = Statement sql encoder (D.singleRow entryRow) True
  where
    sql =
      "INSERT INTO entries (id, log_id, entry_date, quantity, description) \
      \VALUES ($1, $2, $3, $4, $5) \
      \ON CONFLICT (log_id, entry_date) DO UPDATE SET \
      \  quantity    = entries.quantity + excluded.quantity, \
      \  description = CASE WHEN excluded.description <> '' \
      \                     THEN excluded.description \
      \                     ELSE entries.description END, \
      \  updated_at  = now() \
      \RETURNING id, log_id, entry_date, quantity, description, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_) -> c) >$< E.param (E.nonNullable E.date)) <>
      ((\(_,_,_,d,_) -> d) >$< E.param (E.nonNullable E.float8)) <>
      ((\(_,_,_,_,e) -> e) >$< E.param (E.nonNullable E.text))

-- | PUT /api/entries/:id updates quantity and description only (date is immutable).
--   Params: (id, user_id, quantity, description). user_id used for ownership check via join.
updateEntry :: Statement (EntryId, UserId, Double, Text) (Maybe Entry)
updateEntry = Statement sql encoder (D.rowMaybe entryRow) True
  where
    sql =
      "UPDATE entries e SET quantity = $3, description = $4, updated_at = now() \
      \FROM logs l \
      \WHERE e.id = $1 AND e.log_id = l.id AND l.user_id = $2 \
      \RETURNING e.id, e.log_id, e.entry_date, e.quantity, e.description, e.created_at, e.updated_at"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable E.float8)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.text))

deleteEntry :: Statement (EntryId, UserId) Int64
deleteEntry = Statement sql encoder D.rowsAffected True
  where
    sql =
      "DELETE FROM entries WHERE id = $1 AND log_id IN \
      \  (SELECT id FROM logs WHERE user_id = $2)"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | Ownership check for an entry by id (used by entry handlers before update/delete).
getEntryOwner :: Statement EntryId (Maybe UserId)
getEntryOwner = Statement sql encoder decoder True
  where
    sql =
      "SELECT l.user_id FROM entries e JOIN logs l ON e.log_id = l.id \
      \WHERE e.id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe (D.column (D.nonNullable D.text))

entryRow :: D.Row Entry
entryRow =
  Entry
    <$> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.date)
    <*> D.column (D.nonNullable D.float8)
    <*> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.timestamptz)
    <*> D.column (D.nonNullable D.timestamptz)
