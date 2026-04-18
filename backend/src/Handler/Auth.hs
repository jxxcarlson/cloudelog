module Handler.Auth
  ( signupHandler
  , loginHandler
  , logoutHandler
  , meHandler
  ) where

import           Api.Auth                (SetCookies)
import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.User                 as DbUser
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.UUID               (toText)
import qualified Data.UUID.V4            as UUID
import qualified Hasql.Pool              as Pool
import qualified Hasql.Session           as Session
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     ( AuthResult(..), CookieSettings, JWTSettings
                                         , acceptLogin, clearSession )
import           Service.Auth            (AuthUser(..), checkPassword, hashPassword)
import qualified Text.Regex.Posix        as Re
import           Types.User              (User(..))

-- POST /api/auth/signup
signupHandler :: SignupRequest -> AppM (SetCookies NoContent)
signupHandler SignupRequest{..} = do
  validateEmail srEmail
  validatePassword srPassword
  pool <- asks envDbPool
  cs   <- asks envCookieSettings
  js   <- asks envJwtSettings
  uid  <- liftIO $ toText <$> UUID.nextRandom
  mHash <- liftIO $ hashPassword srPassword
  case mHash of
    Nothing -> throwError $ appErrorToServantErr (Internal "password hashing failed")
    Just hash -> do
      r <- liftIO $ Pool.use pool $ Session.statement (uid, srEmail, hash) DbUser.insertUser
      case r of
        Left err
          | isUniqueViolation err ->
              throwError $ appErrorToServantErr (Conflict "email already registered")
          | otherwise ->
              throwError $ appErrorToServantErr (Internal "database error")
        Right () -> issueCookies cs js (AuthUser uid srEmail)

-- POST /api/auth/login
loginHandler :: LoginRequest -> AppM (SetCookies NoContent)
loginHandler LoginRequest{..} = do
  pool <- asks envDbPool
  cs   <- asks envCookieSettings
  js   <- asks envJwtSettings
  r <- liftIO $ Pool.use pool $ Session.statement lrEmail DbUser.getUserByEmail
  case r of
    Left _ -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing -> throwError $ appErrorToServantErr Unauthorized
    Right (Just u) ->
      if checkPassword lrPassword (usrPwHash u)
        then issueCookies cs js (AuthUser (usrId u) (usrEmail u))
        else throwError $ appErrorToServantErr Unauthorized

-- POST /api/auth/logout
logoutHandler :: AppM (SetCookies NoContent)
logoutHandler = do
  cs <- asks envCookieSettings
  pure $ clearSession cs NoContent

-- GET /api/auth/me
meHandler :: AuthResult AuthUser -> AppM UserResponse
meHandler = \case
  Authenticated AuthUser{..} -> pure UserResponse { urId = auUserId, urEmail = auEmail }
  _                          -> throwError $ appErrorToServantErr Unauthorized

---------------------------------------------------------------
-- helpers
---------------------------------------------------------------

issueCookies :: CookieSettings -> JWTSettings -> AuthUser -> AppM (SetCookies NoContent)
issueCookies cs js au = do
  mApply <- liftIO $ acceptLogin cs js au
  case mApply of
    Nothing     -> throwError $ appErrorToServantErr (Internal "cookie creation failed")
    Just apply  -> pure $ apply NoContent

-- Minimal email regex: something@something.something
validateEmail :: Text -> AppM ()
validateEmail e
  | (T.unpack e Re.=~ ("^.+@.+\\..+$" :: String)) = pure ()
  | otherwise = throwError $ appErrorToServantErr (BadRequest "invalid email")

validatePassword :: Text -> AppM ()
validatePassword p
  | T.length p >= 8 = pure ()
  | otherwise = throwError $ appErrorToServantErr (BadRequest "password must be at least 8 characters")

-- Detect a Postgres unique-constraint violation from a Hasql pool error.
-- Hasql surfaces SQLSTATE 23505 as a ResultError. We pattern-match on Show.
isUniqueViolation :: Show e => e -> Bool
isUniqueViolation e = "23505" `T.isInfixOf` T.pack (show e)
