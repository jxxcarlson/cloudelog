module Types.Log (Log(..)) where

import           Data.Text       (Text)
import           Data.Time.Clock (UTCTime)
import           Types.Common    (LogId, UserId)

data Log = Log
  { logId          :: LogId
  , logUserId      :: UserId
  , logName        :: Text
  , logDescription :: Text
  , logUnit        :: Text
  , logCreatedAt   :: UTCTime
  , logUpdatedAt   :: UTCTime
  } deriving (Show, Eq)
