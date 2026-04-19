module Db.Log
  ( insertLog
  , listLogsByUser
  , getLog
  , updateLog
  , deleteLog
  , countLogEntries
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int64)
import           Data.Text                  (Text)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (LogId, UserId)
import           Types.Log                  (Log(..))

-- | INSERT a log. Params: (id, user_id, name, description, unit, start_date).
insertLog :: Statement (LogId, UserId, Text, Text, Text, Day) Log
insertLog = Statement sql encoder (D.singleRow logRow) True
  where
    sql =
      "INSERT INTO logs (id, user_id, name, description, unit, start_date) \
      \VALUES ($1, $2, $3, $4, $5, $6) \
      \RETURNING id, user_id, name, description, unit, start_date, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e,_) -> e) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,_,f) -> f) >$< E.param (E.nonNullable E.date))

listLogsByUser :: Statement UserId (Vector Log)
listLogsByUser = Statement sql encoder (D.rowVector logRow) True
  where
    sql =
      "SELECT id, user_id, name, description, unit, start_date, created_at, updated_at \
      \FROM logs WHERE user_id = $1 ORDER BY updated_at DESC"
    encoder = E.param (E.nonNullable E.text)

-- | Fetch one log by id. Returns Nothing if missing or owned by a different user.
getLog :: Statement (LogId, UserId) (Maybe Log)
getLog = Statement sql encoder (D.rowMaybe logRow) True
  where
    sql =
      "SELECT id, user_id, name, description, unit, start_date, created_at, updated_at \
      \FROM logs WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | UPDATE name, description, and unit. Caller must pre-validate unit immutability.
--   start_date is intentionally NOT updated — it is immutable after creation.
--   Params: (id, user_id, name, description, unit).
updateLog :: Statement (LogId, UserId, Text, Text, Text) (Maybe Log)
updateLog = Statement sql encoder (D.rowMaybe logRow) True
  where
    sql =
      "UPDATE logs \
      \SET name = $3, description = $4, unit = $5, updated_at = now() \
      \WHERE id = $1 AND user_id = $2 \
      \RETURNING id, user_id, name, description, unit, start_date, created_at, updated_at"
    encoder =
      ((\(a,_,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d,_) -> d) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,_,e) -> e) >$< E.param (E.nonNullable E.text))

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

logRow :: D.Row Log
logRow =
  Log
    <$> D.column (D.nonNullable D.text)         -- id
    <*> D.column (D.nonNullable D.text)         -- user_id
    <*> D.column (D.nonNullable D.text)         -- name
    <*> D.column (D.nonNullable D.text)         -- description
    <*> D.column (D.nonNullable D.text)         -- unit
    <*> D.column (D.nonNullable D.date)         -- start_date
    <*> D.column (D.nonNullable D.timestamptz)  -- created_at
    <*> D.column (D.nonNullable D.timestamptz)  -- updated_at
