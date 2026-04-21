module Types.Log (Log(..)) where

import           Data.Text            (Text)
import           Data.Time.Calendar   (Day)
import           Data.Time.Clock      (UTCTime)
import           Data.Vector          (Vector)
import           Types.Common         (LogCollectionId, LogId, UserId)

data Log = Log
  { logId           :: LogId
  , logUserId       :: UserId
  , logName         :: Text
  , logDescription  :: Text
  , logMetricNames  :: Vector Text
  , logMetricUnits  :: Vector Text
  , logStartDate    :: Day
  , logCollectionId :: Maybe LogCollectionId
  , logCreatedAt    :: UTCTime
  , logUpdatedAt    :: UTCTime
  } deriving (Show, Eq)
