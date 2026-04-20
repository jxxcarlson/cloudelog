module Types.Entry (Entry(..)) where

import           Data.Text            (Text)
import           Data.Time.Calendar   (Day)
import           Data.Time.Clock      (UTCTime)
import           Data.Vector          (Vector)
import           Types.Common         (EntryId, LogId)

data Entry = Entry
  { entId           :: EntryId
  , entLogId        :: LogId
  , entDate         :: Day
  , entQuantities   :: Vector Double
  , entDescriptions :: Vector Text
  , entCreatedAt    :: UTCTime
  , entUpdatedAt    :: UTCTime
  } deriving (Show, Eq)
