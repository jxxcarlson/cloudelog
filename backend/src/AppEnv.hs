module AppEnv
  ( AppEnv(..)
  , AppM
  ) where

import           Control.Monad.Reader    (ReaderT)
import qualified Hasql.Pool              as Pool
import           Servant                 (Handler)
import           Servant.Auth.Server     (CookieSettings, JWTSettings)

data AppEnv = AppEnv
  { envDbPool         :: Pool.Pool
  , envJwtSettings    :: JWTSettings
  , envCookieSettings :: CookieSettings
  , envPort           :: Int
  , envJwtExpiryDays  :: Int
  }

type AppM = ReaderT AppEnv Handler
