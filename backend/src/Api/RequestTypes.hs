module Api.RequestTypes where

import           Data.Aeson         ( FromJSON(..), Options(..), ToJSON(..)
                                    , defaultOptions, genericParseJSON, genericToJSON )
import           Data.Char          (toLower)
import           Data.Text          (Text)
import           Data.Time.Calendar (Day)
import           Data.Time.Clock    (UTCTime)
import           GHC.Generics       (Generic)
import           Types.Common       (EntryId, LogId, UserId)

-- Strips a fixed-length camelCase prefix like `srEmail` → `email`.
stripPrefixOptions :: Int -> Options
stripPrefixOptions n = defaultOptions
  { fieldLabelModifier = \s ->
      case drop n s of
        []     -> s
        (c:cs) -> toLower c : cs
  }

-- Auth --------------------------------------------------------------------

data SignupRequest = SignupRequest
  { srEmail    :: Text
  , srPassword :: Text
  } deriving (Show, Generic)
instance FromJSON SignupRequest where parseJSON = genericParseJSON (stripPrefixOptions 2)

data LoginRequest = LoginRequest
  { lrEmail    :: Text
  , lrPassword :: Text
  } deriving (Show, Generic)
instance FromJSON LoginRequest where parseJSON = genericParseJSON (stripPrefixOptions 2)

data UserResponse = UserResponse
  { urId    :: UserId
  , urEmail :: Text
  } deriving (Show, Generic)
instance ToJSON UserResponse where toJSON = genericToJSON (stripPrefixOptions 2)

-- Logs --------------------------------------------------------------------

data MetricSpec = MetricSpec
  { msName :: Text
  , msUnit :: Text
  } deriving (Show, Generic)
instance FromJSON MetricSpec where parseJSON = genericParseJSON (stripPrefixOptions 2)
instance ToJSON   MetricSpec where toJSON    = genericToJSON   (stripPrefixOptions 2)

data CreateLogRequest = CreateLogRequest
  { clrName        :: Text
  , clrMetrics     :: [MetricSpec]
  , clrDescription :: Maybe Text
  , clrStartDate   :: Maybe Day
  } deriving (Show, Generic)
instance FromJSON CreateLogRequest where parseJSON = genericParseJSON (stripPrefixOptions 3)

data UpdateLogRequest = UpdateLogRequest
  { ulrName        :: Text
  , ulrDescription :: Text
  , ulrMetrics     :: Maybe [MetricSpec]
  } deriving (Show, Generic)
instance FromJSON UpdateLogRequest where parseJSON = genericParseJSON (stripPrefixOptions 3)

data LogResponse = LogResponse
  { logrId          :: LogId
  , logrName        :: Text
  , logrMetrics     :: [MetricSpec]
  , logrDescription :: Text
  , logrStartDate   :: Day
  , logrCreatedAt   :: UTCTime
  , logrUpdatedAt   :: UTCTime
  } deriving (Show, Generic)
instance ToJSON LogResponse where toJSON = genericToJSON (stripPrefixOptions 4)

data StreakStats = StreakStats
  { ssCurrent :: Int
  , ssAverage :: Maybe Double
  , ssLongest :: Int
  } deriving (Show, Generic)
instance ToJSON StreakStats where toJSON = genericToJSON (stripPrefixOptions 2)

data LogDetailResponse = LogDetailResponse
  { ldrLog         :: LogResponse
  , ldrEntries     :: [EntryResponse]
  , ldrStreakStats :: StreakStats
  } deriving (Show, Generic)
instance ToJSON LogDetailResponse where toJSON = genericToJSON (stripPrefixOptions 3)

-- Entries -----------------------------------------------------------------

data EntryValue = EntryValue
  { evQuantity    :: Double
  , evDescription :: Text
  } deriving (Show, Generic)
instance FromJSON EntryValue where parseJSON = genericParseJSON (stripPrefixOptions 2)
instance ToJSON   EntryValue where toJSON    = genericToJSON   (stripPrefixOptions 2)

data CreateEntryRequest = CreateEntryRequest
  { cerEntryDate :: Day
  , cerValues    :: [EntryValue]
  } deriving (Show, Generic)
instance FromJSON CreateEntryRequest where parseJSON = genericParseJSON (stripPrefixOptions 3)

data UpdateEntryRequest = UpdateEntryRequest
  { uerValues :: [EntryValue]
  } deriving (Show, Generic)
instance FromJSON UpdateEntryRequest where parseJSON = genericParseJSON (stripPrefixOptions 3)

data EntryResponse = EntryResponse
  { erId         :: EntryId
  , erLogId      :: LogId
  , erEntryDate  :: Day
  , erValues     :: [EntryValue]
  , erCreatedAt  :: UTCTime
  , erUpdatedAt  :: UTCTime
  } deriving (Show, Generic)
instance ToJSON EntryResponse where toJSON = genericToJSON (stripPrefixOptions 2)

data EntriesListResponse = EntriesListResponse
  { elrEntries :: [EntryResponse]
  } deriving (Show, Generic)
instance ToJSON EntriesListResponse where toJSON = genericToJSON (stripPrefixOptions 3)
