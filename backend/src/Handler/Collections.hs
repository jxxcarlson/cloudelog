module Handler.Collections
  ( listCollectionsHandler
  , createCollectionHandler
  , getCollectionHandler
  , updateCollectionHandler
  , deleteCollectionHandler
  , combinedEntryHandler
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Collection           as DbColl
import qualified Db.Entry                as DbEntry
import qualified Db.Log                  as DbLog
import qualified Db.Streak               as DbStreak
import           Control.Monad           (when)
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Int                (Int32)
import qualified Data.Map.Strict         as M
import           Data.Maybe              (fromMaybe)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.Time.Calendar      (Day)
import           Data.Time.Clock         (getCurrentTime, utctDay)
import           Data.UUID               (toText)
import qualified Data.UUID.V4            as UUID
import qualified Data.Vector             as V
import qualified Hasql.Pool              as Pool
import qualified Hasql.Session           as Session
import qualified Hasql.Transaction       as Tx
import qualified Hasql.Transaction.Sessions as Tx
import qualified Handler.Entries         as HE
import           Handler.Logs            (requireUser, toEntryResponse, toLogResponse)
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     (AuthResult)
import           Service.Auth            (AuthUser)
import           Service.SkipFill        (datesToFill)
import           Types.Collection        (Collection(..))
import           Types.Common            (LogCollectionId, LogId, UserId)

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

combinedEntryHandler
  :: AuthResult AuthUser -> Text -> CombinedEntryRequest
  -> AppM CollectionDetailResponse
combinedEntryHandler auth cid CombinedEntryRequest{..} = do
  uid   <- requireUser auth
  pool  <- asks envDbPool
  today <- liftIO (utctDay <$> getCurrentTime)
  when (cmbEntryDate > today) $
    throwError $ appErrorToServantErr (BadRequest "entry date cannot be in the future")

  -- Preflight (outside tx): for each log in the request, read its
  -- current maxEntryDate to size the skip-fill UUID pool, and fetch
  -- the log's metric count to validate values-array length. A concurrent
  -- entry insert could change the max date between this read and the tx;
  -- the skip-fill SQL's ON CONFLICT DO NOTHING absorbs that race.
  let logIds = map leiLogId cmbLogEntries
  preflightPairs <- mapM (preflightForLog pool) logIds
  --    preflightPairs :: [(LogId, Maybe Day, Int32)]

  -- Fail-fast on values-array length mismatches before opening the tx.
  -- Doing this in-tx would let items 1..N-1 commit their writes before
  -- item N's mismatch produced a Left AppError, creating a partial-write
  -- window. The metric count can race with a concurrent metric edit, but
  -- that's the same race a pure in-tx check would have.
  let lengthMismatches =
        [ (lid, expectedN, actualN)
        | (LogEntryItem lid vs, (_, _, mCount)) <- zip cmbLogEntries preflightPairs
        , let expectedN = fromIntegral mCount :: Int
        , let actualN = length vs
        , actualN /= expectedN
        ]
  case lengthMismatches of
    [] -> pure ()
    ((lid, expected, actual) : _) ->
      throwError $ appErrorToServantErr $ BadRequest $ T.pack $
        "values must have " <> show expected
          <> " entries (got " <> show actual <> ") for log " <> T.unpack lid

  -- Pre-generate UUIDs:
  --   * one new-entry UUID per request item
  --   * enough skip-fill UUIDs per item = length (datesToFill mLast entryDate)
  newIds <- liftIO (generateUuids (length cmbLogEntries))
  let skipCountsFor (lid, mLast, _) =
        let d = datesToFill mLast cmbEntryDate
        in  (lid, length d)
      perLogSkipCounts = map skipCountsFor preflightPairs
      totalSkipsNeeded = sum (map snd perLogSkipCounts)
  skipIdsPool <- liftIO (generateUuids totalSkipsNeeded)
  let (perLogSkipIds, _) =
        foldr
          (\(lid, cnt) (acc, remaining) ->
              let (taken, rest) = splitAt cnt remaining
              in  ((lid, taken) : acc, rest))
          ([], skipIdsPool)
          perLogSkipCounts
      skipIdsLookup = M.fromList perLogSkipIds

  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $
      combinedEntryTx cid uid cmbEntryDate cmbLogEntries newIds skipIdsLookup preflightPairs

  case result of
    Left _           -> throwError $ appErrorToServantErr (Internal "database error")
    Right (Left e)   -> throwError $ appErrorToServantErr e
    Right (Right ()) -> pure ()

  getCollectionHandler auth cid

-- | Per-log preflight: read max entry date and metric count in two pool
--   round-trips. Errors surface as a 500.
preflightForLog :: Pool.Pool -> LogId -> AppM (LogId, Maybe Day, Int32)
preflightForLog pool lid = do
  rMax <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.maxEntryDate
  mMax <- case rMax of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right m -> pure m
  rCount <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.getLogMetricCount
  n <- case rCount of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right c -> pure c
  pure (lid, mMax, n)

combinedEntryTx
  :: LogCollectionId
  -> UserId
  -> Day
  -> [LogEntryItem]
  -> [Text]
  -> M.Map LogId [Text]
  -> [(LogId, Maybe Day, Int32)]
  -> Tx.Transaction (Either AppError ())
combinedEntryTx cid uid entryDate items newIds skipIdsLookup preflights = do
  mColl <- Tx.statement (cid, uid) DbColl.getCollection
  case mColl of
    Nothing -> pure (Left NotFound)
    Just _  -> do
      memberIdsV <- Tx.statement cid DbColl.getCollectionMembers
      let memberIds = V.toList memberIdsV
          requestIds = map leiLogId items
          notMembers = filter (`notElem` memberIds) requestIds
      if not (null notMembers)
        then pure (Left (BadRequest (T.pack ("log is not a member of this collection: "
                                             <> T.unpack (T.intercalate ", " notMembers)))))
        else processItems entryDate skipIdsLookup (zip3 items newIds preflights)

processItems
  :: Day
  -> M.Map LogId [Text]
  -> [(LogEntryItem, Text, (LogId, Maybe Day, Int32))]
  -> Tx.Transaction (Either AppError ())
processItems _ _ [] = pure (Right ())
processItems entryDate skipIds ((LogEntryItem lid vs, newId, (_, _mLast, mCount)) : rest) = do
  -- Values-array length was validated pre-tx in combinedEntryHandler;
  -- no need to re-check here. lockLogForUpdate remains the in-tx
  -- ownership/existence gate.
  mUserId <- Tx.statement lid DbEntry.lockLogForUpdate
  case mUserId of
    Nothing -> pure (Left NotFound)
    Just _  -> do
      -- Re-read maxEntryDate inside the tx to get a consistent snapshot.
      mMax <- Tx.statement lid DbEntry.maxEntryDate
      let fillDays     = datesToFill mMax entryDate
          allSkipIds   = fromMaybe [] (M.lookup lid skipIds)
          skipIdsToUse = take (length fillDays) allSkipIds
      _ <- if null fillDays
             then pure ()
             else Tx.statement
                    ( lid
                    , V.fromList skipIdsToUse
                    , V.fromList fillDays
                    , mCount
                    )
                    DbEntry.insertSkipFills
      let qs    = V.fromList (map evQuantity vs)
          descs = V.fromList (map evDescription vs)
      _entry <- Tx.statement
                  (newId, lid, entryDate, qs, descs)
                  DbEntry.upsertEntry
      HE.recomputeStreaksTx lid
      processItems entryDate skipIds rest

generateUuids :: Int -> IO [Text]
generateUuids n
  | n <= 0    = pure []
  | otherwise = mapM (\_ -> toText <$> UUID.nextRandom) [1..n]

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
