module Types.User (User(..)) where

import           Data.Text       (Text)
import           Data.Time.Clock (UTCTime)
import           Types.Common    (LogId, UserId)

data User = User
  { usrId           :: UserId
  , usrEmail        :: Text
  , usrPwHash       :: Text
  , usrCurrentLogId :: Maybe LogId
  , usrCreatedAt    :: UTCTime
  , usrUpdatedAt    :: UTCTime
  } deriving (Show, Eq)
