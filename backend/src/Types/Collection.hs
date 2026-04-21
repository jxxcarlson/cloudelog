module Types.Collection (Collection(..)) where

import           Data.Text          (Text)
import           Data.Time.Clock    (UTCTime)
import           Types.Common       (LogCollectionId, UserId)

data Collection = Collection
  { collId          :: LogCollectionId
  , collUserId      :: UserId
  , collName        :: Text
  , collDescription :: Text
  , collCreatedAt   :: UTCTime
  , collUpdatedAt   :: UTCTime
  } deriving (Show, Eq)
