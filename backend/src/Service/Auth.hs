module Service.Auth
  ( AuthUser(..)
  , hashPassword
  , checkPassword
  , makeJwtSettings
  , expiryFromNow
  , defaultCookieSettingsDev
  , defaultCookieSettingsProd
  ) where

import           Crypto.BCrypt          (hashPasswordUsingPolicy, slowerBcryptHashingPolicy, validatePassword)
import           Crypto.JOSE.JWK        (fromOctets)
import           Data.Aeson             (FromJSON, ToJSON)
import           Data.ByteString        (ByteString)
import           Data.Text              (Text)
import           Data.Text.Encoding     (decodeUtf8, encodeUtf8)
import           Data.Time.Clock        (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import           GHC.Generics           (Generic)
import           Servant.Auth.Server    ( CookieSettings, FromJWT, IsSecure(..), JWTSettings
                                        , SameSite(..), ToJWT
                                        , cookieIsSecure, cookieSameSite, cookieXsrfSetting
                                        , defaultCookieSettings, defaultJWTSettings)
import           Types.Common           (UserId)

-- | Payload embedded in the JWT cookie and passed to authenticated handlers.
data AuthUser = AuthUser
  { auUserId :: UserId
  , auEmail  :: Text
  } deriving (Show, Eq, Generic)

instance FromJSON AuthUser
instance ToJSON   AuthUser
instance FromJWT  AuthUser
instance ToJWT    AuthUser

-- | bcrypt at cost 12 via slowerBcryptHashingPolicy.
hashPassword :: Text -> IO (Maybe Text)
hashPassword password = do
  result <- hashPasswordUsingPolicy slowerBcryptHashingPolicy (encodeUtf8 password)
  pure (decodeUtf8 <$> result)

checkPassword :: Text -> Text -> Bool
checkPassword password hash =
  validatePassword (encodeUtf8 hash) (encodeUtf8 password)

makeJwtSettings :: ByteString -> JWTSettings
makeJwtSettings secret = defaultJWTSettings (fromOctets secret)

-- | Expiry N days from now, used when issuing a cookie.
expiryFromNow :: Int -> IO UTCTime
expiryFromNow days = do
  now <- getCurrentTime
  pure $ addUTCTime (fromIntegral days * nominalDay) now

-- | Dev-mode cookie settings:
--   * cookieIsSecure = NotSecure  — HTTP localhost is OK
--   * cookieSameSite = SameSiteLax
--   * XSRF disabled for simplicity (pure JSON API, no HTML forms with cookies)
defaultCookieSettingsDev :: CookieSettings
defaultCookieSettingsDev = defaultCookieSettings
  { cookieIsSecure    = NotSecure
  , cookieSameSite    = SameSiteLax
  , cookieXsrfSetting = Nothing
  }

-- | Production cookie settings: same as Dev but with the Secure flag set,
--   so the browser only sends the JWT cookie over HTTPS.
defaultCookieSettingsProd :: CookieSettings
defaultCookieSettingsProd = defaultCookieSettingsDev
  { cookieIsSecure = Secure }
