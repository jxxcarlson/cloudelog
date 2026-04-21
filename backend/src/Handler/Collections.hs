module Handler.Collections
  ( listCollectionsHandler
  , createCollectionHandler
  , getCollectionHandler
  , updateCollectionHandler
  , deleteCollectionHandler
  , combinedEntryHandler  -- stub; implemented in Task 5
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Collection           as DbColl
import qualified Db.Entry                as DbEntry
import qualified Db.Log                  as DbLog
import qualified Db.Streak               as DbStreak
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
import           Handler.Logs            (requireUser, toEntryResponse, toLogResponse)
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     (AuthResult)
import           Service.Auth            (AuthUser)
import           Types.Collection        (Collection(..))
import           Types.Common            (LogId, UserId)

listCollectionsHandler :: AuthResult AuthUser -> AppM [CollectionSummaryResponse]
listCollectionsHandler auth = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $ Session.statement uid DbColl.listCollectionsByUser
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right v -> pure (map toSummary (V.toList v))

createCollectionHandler :: AuthResult AuthUser -> CreateCollectionRequest -> AppM CollectionResponse
createCollectionHandler auth CreateCollectionRequest{..} = do
  uid <- requireUser auth
  validateName ccrName
  pool <- asks envDbPool
  cid  <- liftIO $ toText <$> UUID.nextRandom
  let desc = fromMaybe "" ccrDescription
  r <- liftIO $ Pool.use pool $
         Session.statement (cid, uid, T.strip ccrName, desc) DbColl.insertCollection
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right c -> pure (toCollectionResponse c)

getCollectionHandler :: AuthResult AuthUser -> Text -> AppM CollectionDetailResponse
getCollectionHandler auth cid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  rColl <- liftIO $ Pool.use pool $ Session.statement (cid, uid) DbColl.getCollection
  coll <- case rColl of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just c) -> pure c
  rIds <- liftIO $ Pool.use pool $ Session.statement cid DbColl.getCollectionMembers
  memberIds <- case rIds of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right v -> pure (V.toList v)
  members <- mapM (loadMember pool uid) memberIds
  pure CollectionDetailResponse
    { cdrCollection = toCollectionResponse coll
    , cdrMembers    = members
    }

updateCollectionHandler :: AuthResult AuthUser -> Text -> UpdateCollectionRequest -> AppM CollectionResponse
updateCollectionHandler auth cid UpdateCollectionRequest{..} = do
  uid <- requireUser auth
  validateName ucrName
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $
         Session.statement (cid, uid, T.strip ucrName, ucrDescription) DbColl.updateCollection
  case r of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just c) -> pure (toCollectionResponse c)

deleteCollectionHandler :: AuthResult AuthUser -> Text -> AppM NoContent
deleteCollectionHandler auth cid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $ Session.statement (cid, uid) DbColl.deleteCollection
  case r of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right 0 -> throwError $ appErrorToServantErr NotFound
    Right _ -> pure NoContent

combinedEntryHandler :: AuthResult AuthUser -> Text -> CombinedEntryRequest -> AppM CollectionDetailResponse
combinedEntryHandler _auth _cid _req =
  throwError $ appErrorToServantErr (Internal "combined-entry not yet implemented")

---------------------------------------------------------------
-- helpers
---------------------------------------------------------------

toCollectionResponse :: Collection -> CollectionResponse
toCollectionResponse c = CollectionResponse
  { crId          = collId c
  , crName        = collName c
  , crDescription = collDescription c
  , crCreatedAt   = collCreatedAt c
  , crUpdatedAt   = collUpdatedAt c
  }

toSummary :: DbColl.CollectionSummaryRow -> CollectionSummaryResponse
toSummary (DbColl.CollectionSummaryRow c n) = CollectionSummaryResponse
  { csrId          = collId c
  , csrName        = collName c
  , csrDescription = collDescription c
  , csrMemberCount = fromIntegral n
  , csrCreatedAt   = collCreatedAt c
  , csrUpdatedAt   = collUpdatedAt c
  }

loadMember :: Pool.Pool -> UserId -> LogId -> AppM CollectionMember
loadMember pool uid lid = do
  rLog <- liftIO $ Pool.use pool $ Session.statement (lid, uid) DbLog.getLog
  l <- case rLog of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr (Internal "member log vanished")
    Right (Just v) -> pure v
  rEntries <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.listEntriesByLog
  entries <- case rEntries of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right v -> pure (V.toList v)
  rStats <- liftIO $ Pool.use pool $ Session.statement lid DbStreak.selectStreakStats
  stats <- case rStats of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right s -> pure s
  pure CollectionMember
    { cmLog         = toLogResponse l
    , cmEntries     = map toEntryResponse entries
    , cmStreakStats = toStreakStats stats
    }

toStreakStats :: DbStreak.StreakStatsRow -> StreakStats
toStreakStats DbStreak.StreakStatsRow{..} = StreakStats
  { ssCurrent = fromIntegral ssrCurrent
  , ssAverage = ssrAverage
  , ssLongest = fromIntegral ssrLongest
  }

validateName :: Text -> AppM ()
validateName n
  | T.null (T.strip n) = throwError $ appErrorToServantErr (BadRequest "name cannot be empty")
  | T.length n > 200   = throwError $ appErrorToServantErr (BadRequest "name too long (max 200)")
  | otherwise          = pure ()
