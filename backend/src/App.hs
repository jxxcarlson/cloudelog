module App (startApp) where

import           Api.Types                  (CloudelogAPI)
import           AppEnv                     (AppEnv(..), AppM)
import           Config                     (Config(..))
import qualified Db.Pool                    as Db
import qualified Handler.Auth               as H
import qualified Handler.Entries            as H
import qualified Handler.Logs               as H
import           Control.Monad.Reader       (runReaderT)
import qualified Data.ByteString.Char8      as BS
import           Network.Wai                (Middleware, rawPathInfo, rawQueryString, requestMethod)
import           Network.Wai.Handler.Warp   (run)
import           Network.Wai.Middleware.Cors
import           Servant
import           Servant.Auth.Server        (CookieSettings, JWTSettings)
import           Service.Auth               (defaultCookieSettingsDev, makeJwtSettings)
import           System.IO                  (hFlush, stdout)

startApp :: Config -> IO ()
startApp cfg = do
  pool <- Db.createPool (configDbUrl cfg)
  let env = AppEnv
        { envDbPool         = pool
        , envJwtSettings    = makeJwtSettings (configJwtSecret cfg)
        , envCookieSettings = defaultCookieSettingsDev
        , envPort           = configPort cfg
        , envJwtExpiryDays  = configJwtExpiryDays cfg
        }
  putStrLn $ "cloudelog backend listening on port " <> show (configPort cfg)
  run (configPort cfg) (requestLogger (corsMiddleware (mkApp env)))

-- | Log method + path for every request so we can see what the frontend sends.
requestLogger :: Middleware
requestLogger app req respond = do
  putStrLn $
    BS.unpack (requestMethod req)
      <> " "
      <> BS.unpack (rawPathInfo req)
      <> BS.unpack (rawQueryString req)
  hFlush stdout
  app req respond

corsMiddleware :: Application -> Application
corsMiddleware = cors (const (Just policy))
  where
    policy = simpleCorsResourcePolicy
      { corsOrigins        = Just (["http://localhost:8011"], True) -- credentials allowed only for this origin
      , corsMethods        = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
      , corsRequestHeaders = ["Authorization", "Content-Type"]
      }

mkApp :: AppEnv -> Application
mkApp env =
  let ctx = envCookieSettings env :. envJwtSettings env :. EmptyContext
  in  serveWithContext (Proxy :: Proxy CloudelogAPI) ctx (server env)

server :: AppEnv -> Server CloudelogAPI
server env =
  hoistServerWithContext
    (Proxy :: Proxy CloudelogAPI)
    (Proxy :: Proxy '[CookieSettings, JWTSettings])
    (nt env)
    serverT
  where
    nt :: AppEnv -> AppM a -> Handler a
    nt e action = runReaderT action e

serverT :: ServerT CloudelogAPI AppM
serverT =
       authServer
  :<|> logsServer
  :<|> entriesServer
  :<|> healthHandler
  where
    authServer =
           H.signupHandler
      :<|> H.loginHandler
      :<|> H.logoutHandler
      :<|> H.meHandler
    logsServer auth =
           H.listLogsHandler   auth
      :<|> H.createLogHandler  auth
      :<|> H.getLogHandler     auth
      :<|> H.updateLogHandler  auth
      :<|> H.deleteLogHandler  auth
      :<|> H.postEntryHandler  auth
    entriesServer auth =
           H.updateEntryHandler auth
      :<|> H.deleteEntryHandler auth
    healthHandler :: AppM String
    healthHandler = pure "ok"
