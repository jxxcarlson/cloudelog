module Config
  ( Config(..)
  , loadConfig
  ) where

import           Data.ByteString      (ByteString)
import qualified Data.ByteString.Char8 as BS
import           System.Environment   (lookupEnv)
import           Text.Read            (readMaybe)

data Config = Config
  { configDbUrl         :: ByteString
  , configJwtSecret     :: ByteString
  , configJwtExpiryDays :: Int
  , configPort          :: Int
  }

instance Show Config where
  show c =
    "Config { configDbUrl = <hidden>, configJwtSecret = <hidden>" <>
    ", configJwtExpiryDays = " <> show (configJwtExpiryDays c) <>
    ", configPort = " <> show (configPort c) <> " }"

loadConfig :: IO Config
loadConfig = do
  dbUrl    <- envBS "DATABASE_URL" "postgres://localhost/cloudelog_dev"
  secret   <- envBS "JWT_SECRET"   "dev-secret-change-in-production-min-32-chars!!"
  expDays  <- envInt "JWT_EXPIRY_DAYS" 30
  port     <- envInt "PORT" 8081
  pure Config
    { configDbUrl         = dbUrl
    , configJwtSecret     = secret
    , configJwtExpiryDays = expDays
    , configPort          = port
    }
  where
    envBS k dflt = maybe (BS.pack dflt) BS.pack <$> lookupEnv k
    envInt k dflt = do
      mv <- lookupEnv k
      pure $ maybe dflt id (mv >>= readMaybe)
