module Db.Collection
  ( insertCollection
  , listCollectionsByUser
  , getCollection
  , updateCollection
  , deleteCollection
  , getCollectionMembers
  , CollectionSummaryRow(..)
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int32, Int64)
import           Data.Text                  (Text)
import           Data.Vector                (Vector)
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Collection           (Collection(..))
import           Types.Common               (LogCollectionId, UserId)

insertCollection
  :: Statement (LogCollectionId, UserId, Text, Text) Collection
insertCollection = Statement sql encoder (D.singleRow collRow) True
  where
    sql =
      "INSERT INTO log_collections (id, user_id, name, description) \
      \VALUES ($1, $2, $3, $4) \
      \RETURNING id, user_id, name, description, created_at, updated_at"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.text))

-- | Per-collection summary for the list view. Returns the collection row plus
--   a live member count via a correlated subquery.
data CollectionSummaryRow = CollectionSummaryRow
  { csrCollection  :: Collection
  , csrMemberCount :: Int32
  } deriving (Show, Eq)

listCollectionsByUser :: Statement UserId (Vector CollectionSummaryRow)
listCollectionsByUser = Statement sql encoder (D.rowVector summaryRow) True
  where
    sql =
      "SELECT c.id, c.user_id, c.name, c.description, c.created_at, c.updated_at, \
      \       (SELECT count(*) FROM logs l WHERE l.collection_id = c.id)::int \
      \         AS member_count \
      \FROM log_collections c \
      \WHERE c.user_id = $1 \
      \ORDER BY c.updated_at DESC"
    encoder = E.param (E.nonNullable E.text)

summaryRow :: D.Row CollectionSummaryRow
summaryRow = CollectionSummaryRow <$> collRow <*> D.column (D.nonNullable D.int4)

getCollection :: Statement (LogCollectionId, UserId) (Maybe Collection)
getCollection = Statement sql encoder (D.rowMaybe collRow) True
  where
    sql =
      "SELECT id, user_id, name, description, created_at, updated_at \
      \FROM log_collections WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

updateCollection
  :: Statement (LogCollectionId, UserId, Text, Text) (Maybe Collection)
updateCollection = Statement sql encoder (D.rowMaybe collRow) True
  where
    sql =
      "UPDATE log_collections \
      \SET name = $3, description = $4, updated_at = now() \
      \WHERE id = $1 AND user_id = $2 \
      \RETURNING id, user_id, name, description, created_at, updated_at"
    encoder =
      ((\(a,_,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_,_) -> b) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,c,_) -> c) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,_,_,d) -> d) >$< E.param (E.nonNullable E.text))

deleteCollection :: Statement (LogCollectionId, UserId) Int64
deleteCollection = Statement sql encoder D.rowsAffected True
  where
    sql = "DELETE FROM log_collections WHERE id = $1 AND user_id = $2"
    encoder =
      (fst >$< E.param (E.nonNullable E.text)) <>
      (snd >$< E.param (E.nonNullable E.text))

-- | Returns the log_ids of every member of a collection, ordered by the
--   member log's created_at ascending (stable UI ordering).
getCollectionMembers :: Statement LogCollectionId (Vector Text)
getCollectionMembers = Statement sql encoder decoder True
  where
    sql =
      "SELECT id FROM logs \
      \WHERE collection_id = $1 \
      \ORDER BY created_at ASC"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowVector (D.column (D.nonNullable D.text))

collRow :: D.Row Collection
collRow =
  Collection
    <$> D.column (D.nonNullable D.text)         -- id
    <*> D.column (D.nonNullable D.text)         -- user_id
    <*> D.column (D.nonNullable D.text)         -- name
    <*> D.column (D.nonNullable D.text)         -- description
    <*> D.column (D.nonNullable D.timestamptz)  -- created_at
    <*> D.column (D.nonNullable D.timestamptz)  -- updated_at
