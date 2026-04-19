module Types.Log (Log(..)) where

import           Data.Text            (Text)
import           Data.Time.Calendar   (Day)
import           Data.Time.Clock      (UTCTime)
import           Types.Common         (LogId, UserId)

data Log = Log
  { logId          :: LogId
  , logUserId      :: UserId
  , logName        :: Text
  , logDescription :: Text
  , logUnit        :: Text
  , logStartDate   :: Day
  , logCreatedAt   :: UTCTime
  , logUpdatedAt   :: UTCTime
  } deriving (Show, Eq)
