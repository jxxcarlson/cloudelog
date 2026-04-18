module Db.User
  ( insertUser
  , getUserByEmail
  , getUserById
  , setCurrentLogId
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Text                  (Text)
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (LogId, UserId)
import           Types.User                 (User(..))

-- | INSERT a user. Params: (id, email, pw_hash).
insertUser :: Statement (UserId, Text, Text) ()
insertUser = Statement sql encoder D.noResult True
  where
    sql = "INSERT INTO users (id, email, pw_hash) VALUES ($1, $2, $3)"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable E.text))

-- | Fetch a user by email (for login).
getUserByEmail :: Statement Text (Maybe User)
getUserByEmail = Statement sql encoder decoder True
  where
    sql =
      "SELECT id, email, pw_hash, current_log_id, created_at, updated_at \
      \FROM users WHERE email = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow

-- | Fetch a user by id.
getUserById :: Statement UserId (Maybe User)
getUserById = Statement sql encoder decoder True
  where
    sql =
      "SELECT id, email, pw_hash, current_log_id, created_at, updated_at \
      \FROM users WHERE id = $1"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowMaybe userRow

-- | Update the authenticated user's current_log_id.
setCurrentLogId :: Statement (UserId, LogId) ()
setCurrentLogId = Statement sql encoder D.noResult True
  where
    sql =
      "UPDATE users SET current_log_id = $2, updated_at = now() \
      \WHERE id = $1"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

userRow :: D.Row User
userRow =
  User
    <$> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.text)
    <*> D.column (D.nonNullable D.text)
    <*> D.column (D.nullable    D.text)
    <*> D.column (D.nonNullable D.timestamptz)
    <*> D.column (D.nonNullable D.timestamptz)
