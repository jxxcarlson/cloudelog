module Handler.Logs
  ( requireUser
  , toEntryResponse
  , listLogsHandler
  , createLogHandler
  , getLogHandler
  , updateLogHandler
  , deleteLogHandler
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Entry                as DbEntry
import qualified Db.Log                  as DbLog
import qualified Db.User                 as DbUser
import           Control.Monad           (when)
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Maybe              (fromMaybe)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.UUID               (toText)
import qualified Data.UUID.V4            as UUID
import qualified Data.Vector             as V
import qualified Hasql.Pool              as Pool
import qualified Hasql.Session           as Session
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     (AuthResult(..))
import           Service.Auth            (AuthUser(..))
import           Types.Common            (UserId)
import           Types.Log               (Log(..))
import           Types.Entry             (Entry(..))

-- | Extract UserId from an AuthResult or throw 401.
requireUser :: AuthResult AuthUser -> AppM UserId
requireUser = \case
  Authenticated au -> pure (auUserId au)
  _                -> throwError $ appErrorToServantErr Unauthorized

-- GET /api/logs
listLogsHandler :: AuthResult AuthUser -> AppM [LogResponse]
listLogsHandler auth = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $ Session.statement uid DbLog.listLogsByUser
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right v -> pure $ map toLogResponse (V.toList v)

-- POST /api/logs
createLogHandler :: AuthResult AuthUser -> CreateLogRequest -> AppM LogResponse
createLogHandler auth CreateLogRequest{..} = do
  uid <- requireUser auth
  validateUnit clrUnit
  validateName clrName
  pool <- asks envDbPool
  lid  <- liftIO $ toText <$> UUID.nextRandom
  let desc = fromMaybe "" clrDescription
  r <- liftIO $ Pool.use pool $
         Session.statement (lid, uid, clrName, desc, normalizeUnit clrUnit) DbLog.insertLog
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right l -> pure (toLogResponse l)

-- GET /api/logs/:id
-- Side effect: sets users.current_log_id = :id for the authenticated user.
getLogHandler :: AuthResult AuthUser -> Text -> AppM LogDetailResponse
getLogHandler auth lid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  rLog <- liftIO $ Pool.use pool $ Session.statement (lid, uid) DbLog.getLog
  case rLog of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just l) -> do
      rEntries <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.listEntriesByLog
      entries <- case rEntries of
        Left _  -> throwError $ appErrorToServantErr (Internal "database error")
        Right v -> pure (V.toList v)
      -- Fire-and-forget: update current_log_id. Don't fail the request on error.
      _ <- liftIO $ Pool.use pool $ Session.statement (uid, lid) DbUser.setCurrentLogId
      pure LogDetailResponse
        { ldrLog     = toLogResponse l
        , ldrEntries = map toEntryResponse entries
        }

-- PUT /api/logs/:id
updateLogHandler :: AuthResult AuthUser -> Text -> UpdateLogRequest -> AppM LogResponse
updateLogHandler auth lid UpdateLogRequest{..} = do
  uid <- requireUser auth
  validateName ulrName
  pool <- asks envDbPool

  -- Fetch existing log to check ownership AND current unit.
  rExisting <- liftIO $ Pool.use pool $ Session.statement (lid, uid) DbLog.getLog
  existing <- case rExisting of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just l) -> pure l

  -- If caller sent a new unit, enforce "only when no entries".
  newUnit <- case ulrUnit of
    Nothing -> pure (logUnit existing)
    Just u  -> do
      validateUnit u
      let u' = normalizeUnit u
      when (u' /= logUnit existing) $ do
        rCount <- liftIO $ Pool.use pool $ Session.statement lid DbLog.countLogEntries
        case rCount of
          Left _  -> throwError $ appErrorToServantErr (Internal "database error")
          Right 0 -> pure ()
          Right _ -> throwError $ appErrorToServantErr
                       (BadRequest "Cannot change unit of a log that has entries")
      pure u'

  r <- liftIO $ Pool.use pool $
         Session.statement (lid, uid, ulrName, ulrDescription, newUnit) DbLog.updateLog
  case r of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just l) -> pure (toLogResponse l)

-- DELETE /api/logs/:id
deleteLogHandler :: AuthResult AuthUser -> Text -> AppM NoContent
deleteLogHandler auth lid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $ Session.statement (lid, uid) DbLog.deleteLog
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right 0 -> throwError $ appErrorToServantErr NotFound
    Right _ -> pure NoContent

---------------------------------------------------------------
-- conversions + validation
---------------------------------------------------------------

toLogResponse :: Log -> LogResponse
toLogResponse l = LogResponse
  { logrId          = logId l
  , logrName        = logName l
  , logrUnit        = logUnit l
  , logrDescription = logDescription l
  , logrCreatedAt   = logCreatedAt l
  , logrUpdatedAt   = logUpdatedAt l
  }

toEntryResponse :: Entry -> EntryResponse
toEntryResponse e = EntryResponse
  { erId          = entId e
  , erLogId       = entLogId e
  , erEntryDate   = entDate e
  , erQuantity    = entQuantity e
  , erDescription = entDescription e
  , erCreatedAt   = entCreatedAt e
  , erUpdatedAt   = entUpdatedAt e
  }

validateName :: Text -> AppM ()
validateName n
  | T.null (T.strip n) = throwError $ appErrorToServantErr (BadRequest "name cannot be empty")
  | T.length n > 200   = throwError $ appErrorToServantErr (BadRequest "name too long")
  | otherwise          = pure ()

validateUnit :: Text -> AppM ()
validateUnit u
  | T.null (T.strip u) = throwError $ appErrorToServantErr (BadRequest "unit cannot be empty")
  | T.length u > 32    = throwError $ appErrorToServantErr (BadRequest "unit too long (max 32)")
  | otherwise          = pure ()

-- Lowercase the four standard units; pass custom strings through unchanged.
normalizeUnit :: Text -> Text
normalizeUnit u =
  let lower = T.toLower u
  in  if lower `elem` ["minutes", "hours", "kilometers", "miles"]
        then lower
        else u
