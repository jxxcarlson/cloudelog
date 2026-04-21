module App (startApp) where

import           Api.Types                  (CloudelogAPI)
import           AppEnv                     (AppEnv(..), AppM)
import           Config                     (Config(..))
import qualified Db.Pool                    as Db
import qualified Handler.Auth               as H
import qualified Handler.Collections        as H
import qualified Handler.Entries            as H
import qualified Handler.Logs               as H
import           Control.Monad.Reader       (runReaderT)
import qualified Data.ByteString.Char8      as BS
import           Data.Char                  (toLower)
import           Data.List                  (intercalate)
import           Network.Wai                (Middleware, rawPathInfo, rawQueryString, requestMethod)
import           Network.Wai.Handler.Warp   (run)
import           Network.Wai.Middleware.Cors
import           Servant
import           Servant.Auth.Server        (CookieSettings, JWTSettings)
import           Service.Auth               (defaultCookieSettingsDev, defaultCookieSettingsProd, makeJwtSettings)
import           System.Environment         (lookupEnv)
import           System.IO                  (hFlush, stdout)

startApp :: Config -> IO ()
startApp cfg = do
  pool <- Db.createPool (configDbUrl cfg)
  cookieSecure <- maybe False ((== "true") . map toLower) <$> lookupEnv "COOKIE_SECURE"
  origins <- readCorsOrigins
  let cookieSettings =
        if cookieSecure then defaultCookieSettingsProd else defaultCookieSettingsDev
      env = AppEnv
        { envDbPool         = pool
        , envJwtSettings    = makeJwtSettings (configJwtSecret cfg)
        , envCookieSettings = cookieSettings
        , envPort           = configPort cfg
        , envJwtExpiryDays  = configJwtExpiryDays cfg
        }
  putStrLn $ "cloudelog backend listening on port " <> show (configPort cfg)
                <> " (cookieSecure=" <> show cookieSecure <> ")"
                <> " (corsOrigins=" <> intercalate "," (map BS.unpack origins) <> ")"
  run (configPort cfg) (requestLogger (corsMiddleware origins (mkApp env)))

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

corsMiddleware :: [BS.ByteString] -> Application -> Application
corsMiddleware origins = cors (const (Just policy))
  where
    policy = simpleCorsResourcePolicy
      { corsOrigins        = Just (origins, True) -- credentials allowed for these origins only
      , corsMethods        = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
      , corsRequestHeaders = ["Authorization", "Content-Type"]
      }

-- Read CORS_ALLOWED_ORIGINS (comma-separated) from the environment.
-- Defaults to the dev frontend origin when unset.
readCorsOrigins :: IO [BS.ByteString]
readCorsOrigins = do
  raw <- lookupEnv "CORS_ALLOWED_ORIGINS"
  pure $ case raw of
    Nothing -> ["http://localhost:8011"]
    Just s  ->
      let parts = filter (not . null) (map trim (splitOn ',' s))
      in if null parts then ["http://localhost:8011"] else map BS.pack parts
  where
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse
    splitOn c xs = case break (== c) xs of
      (a, [])     -> [a]
      (a, _:rest) -> a : splitOn c rest

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
  :<|> collectionsServer
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
    collectionsServer auth =
           H.listCollectionsHandler   auth
      :<|> H.createCollectionHandler  auth
      :<|> H.getCollectionHandler     auth
      :<|> H.updateCollectionHandler  auth
      :<|> H.deleteCollectionHandler  auth
      :<|> H.combinedEntryHandler     auth
    healthHandler :: AppM String
    healthHandler = pure "ok"
