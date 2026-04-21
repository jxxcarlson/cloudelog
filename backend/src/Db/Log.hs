module Db.Log
  ( insertLog
  , listLogsByUser
  , getLog
  , updateLog
  , setLogCollection
  , deleteLog
  , countLogEntries
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int64)
import           Data.Text                  (Text)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Data.Vector                as V
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (LogCollectionId, LogId, UserId)
import           Types.Log                  (Log(..))

-- | INSERT a log. Params: (id, user_id, name, description, metric_names, metric_units, start_date).
insertLog
  :: Statement (LogId, UserId, Text, Text, Vector Text, Vector Text, Day) Log
insertLog = Statement sql encoder (D.singleRow logRow) True
  where
    sql =
      "INSERT INTO logs (id, user_id, name, description, metric_names, metric_units, start_date) \
      \VALUES ($1, $2, $3, $4, $5, $6, $7) \
      \RETURNING id, user_id, name, description, metric_names, metric_units, start_date, collection_id, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_,_) -> e) >$< E.param (E.nonNullable textArrayE)) <>
      ((\(_,_,_,_,_,f,_) -> f) >$< E.param (E.nonNullable textArrayE)) <>
      ((\(_,_,_,_,_,_,g) -> g) >$< E.param (E.nonNullable E.date))

listLogsByUser :: Statement UserId (Vector Log)
listLogsByUser = Statement sql encoder (D.rowVector logRow) True
  where
    sql =
      "SELECT id, user_id, name, description, metric_names, metric_units, start_date, collection_id, created_at, updated_at \
      \FROM logs WHERE user_id = $1 ORDER BY updated_at DESC"
    encoder = E.param (E.nonNullable E.text)

-- | Fetch one log by id. Returns Nothing if missing or owned by a different user.
getLog :: Statement (LogId, UserId) (Maybe Log)
getLog = Statement sql encoder (D.rowMaybe logRow) True
  where
    sql =
      "SELECT id, user_id, name, description, metric_names, metric_units, start_date, collection_id, created_at, updated_at \
      \FROM logs WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | UPDATE name, description, and metric arrays. Caller must pre-validate
--   that structural changes only happen on empty logs. start_date is
--   intentionally NOT updated.
--   Params: (id, user_id, name, description, metric_names, metric_units).
updateLog
  :: Statement (LogId, UserId, Text, Text, Vector Text, Vector Text) (Maybe Log)
updateLog = Statement sql encoder (D.rowMaybe logRow) True
  where
    sql =
      "UPDATE logs \
      \SET name = $3, description = $4, metric_names = $5, metric_units = $6, updated_at = now() \
      \WHERE id = $1 AND user_id = $2 \
      \RETURNING id, user_id, name, description, metric_names, metric_units, start_date, collection_id, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable textArrayE)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable textArrayE))

-- | Assign a log to a collection, or release it to standalone if the collection
--   id is Nothing. Validates ownership of both the log and (when non-null) the
--   target collection in a single WHERE — if the target collection belongs to a
--   different user, the UPDATE touches zero rows and returns Nothing.
setLogCollection
  :: Statement (LogId, UserId, Maybe LogCollectionId) (Maybe Log)
setLogCollection = Statement sql encoder (D.rowMaybe logRow) True
  where
    sql =
      "UPDATE logs l \
      \SET collection_id = $3, updated_at = now() \
      \WHERE l.id = $1 AND l.user_id = $2 \
      \  AND ($3 IS NULL \
      \       OR EXISTS (SELECT 1 FROM log_collections c \
      \                  WHERE c.id = $3 AND c.user_id = $2)) \
      \RETURNING l.id, l.user_id, l.name, l.description, l.metric_names, \
      \          l.metric_units, l.start_date, l.collection_id, \
      \          l.created_at, l.updated_at"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c) -> c) >$< E.param (E.nullable    E.text))

deleteLog :: Statement (LogId, UserId) Int64
deleteLog = Statement sql encoder D.rowsAffected True
  where
    sql = "DELETE FROM logs WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | Used to enforce "cannot change unit once log has entries".
countLogEntries :: Statement LogId Int64
countLogEntries = Statement sql encoder decoder True
  where
    sql     = "SELECT count(*) FROM entries WHERE log_id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.singleRow (D.column (D.nonNullable D.int8))

-- Reusable array encoder for TEXT[] parameters.
textArrayE :: E.Value (Vector Text)
textArrayE = E.array (E.dimension foldl (E.element (E.nonNullable E.text)))

-- Reusable array decoder for TEXT[] columns.
textArrayD :: D.Value (Vector Text)
textArrayD = D.array (D.dimension V.replicateM (D.element (D.nonNullable D.text)))

logRow :: D.Row Log
logRow =
  Log
    <$> D.column (D.nonNullable D.text)              -- id
    <*> D.column (D.nonNullable D.text)              -- user_id
    <*> D.column (D.nonNullable D.text)              -- name
    <*> D.column (D.nonNullable D.text)              -- description
    <*> D.column (D.nonNullable textArrayD)          -- metric_names
    <*> D.column (D.nonNullable textArrayD)          -- metric_units
    <*> D.column (D.nonNullable D.date)              -- start_date
    <*> D.column (D.nullable    D.text)              -- collection_id
    <*> D.column (D.nonNullable D.timestamptz)       -- created_at
    <*> D.column (D.nonNullable D.timestamptz)       -- updated_at
