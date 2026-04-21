module Handler.Logs
  ( requireUser
  , toEntryResponse
  , listLogsHandler
  , createLogHandler
  , getLogHandler
  , updateLogHandler
  , deleteLogHandler
  , normalizeMetric
  , validateMetrics
  , validateName
  , normalizeUnit
  , validateUnit
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Entry                as DbEntry
import qualified Db.Log                  as DbLog
import qualified Db.Streak               as DbStreak
import qualified Db.User                 as DbUser
import           Control.Monad           (unless, when)
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Int                (Int32)
import           Data.Maybe              (fromMaybe)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.Time.Calendar      (Day, addDays)
import           Data.Time.Clock         (getCurrentTime, utctDay)
import           Data.UUID               (toText)
import qualified Data.UUID.V4            as UUID
import qualified Data.Vector             as V
import qualified Hasql.Pool              as Pool
import qualified Hasql.Session           as Session
import qualified Hasql.Transaction       as Tx
import qualified Hasql.Transaction.Sessions as Tx
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     (AuthResult(..))
import           Service.Auth            (AuthUser(..))
import           Service.SkipFill        (datesToFill)
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
-- In a single transaction: insert the log, and if startDate < today,
-- bulk-insert zero-quantity skip entries for [startDate, today).
createLogHandler :: AuthResult AuthUser -> CreateLogRequest -> AppM LogResponse
createLogHandler auth CreateLogRequest{..} = do
  uid <- requireUser auth
  validateName clrName
  validateMetrics clrMetrics
  pool  <- asks envDbPool
  today <- liftIO (utctDay <$> getCurrentTime)
  startDate <- case clrStartDate of
    Nothing -> pure today
    Just d  -> do
      when (d > today) $
        throwError $ appErrorToServantErr (BadRequest "start date cannot be in the future")
      pure d
  lid <- liftIO $ toText <$> UUID.nextRandom
  let desc          = fromMaybe "" clrDescription
      normMetrics   = map normalizeMetric clrMetrics
      metricNames   = V.fromList (map msName normMetrics)
      metricUnits   = V.fromList (map msUnit normMetrics)
      metricCount   = fromIntegral (length normMetrics) :: Int32
      fillDays      = datesToFill (Just (addDays (-1) startDate)) today
  fillIds <- liftIO $ generateUuids (length fillDays)
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      l <- Tx.statement
             (lid, uid, clrName, desc, metricNames, metricUnits, startDate)
             DbLog.insertLog
      unless (null fillDays) $
        Tx.statement
          (lid, V.fromList fillIds, V.fromList fillDays, metricCount)
          DbEntry.insertSkipFills
      pure l
  case result of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right l -> pure (toLogResponse l)

generateUuids :: Int -> IO [Text]
generateUuids n
  | n <= 0    = pure []
  | otherwise = mapM (\_ -> toText <$> UUID.nextRandom) [1..n]

-- GET /api/logs/:id
-- Side effect: sets users.current_log_id = :id for the authenticated user.
getLogHandler :: AuthResult AuthUser -> Text -> AppM LogDetailResponse
getLogHandler auth lid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.RepeatableRead Tx.Read $ do
      mLog <- Tx.statement (lid, uid) DbLog.getLog
      case mLog of
        Nothing -> pure Nothing
        Just l  -> do
          es    <- Tx.statement lid DbEntry.listEntriesByLog
          stats <- Tx.statement lid DbStreak.selectStreakStats
          pure (Just (l, es, stats))
  case result of
    Left _         -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing  -> throwError $ appErrorToServantErr NotFound
    Right (Just (l, es, stats)) -> do
      -- Fire-and-forget: update current_log_id. Don't fail the request on error.
      _ <- liftIO $ Pool.use pool $ Session.statement (uid, lid) DbUser.setCurrentLogId
      pure LogDetailResponse
        { ldrLog         = toLogResponse l
        , ldrEntries     = map toEntryResponse (V.toList es)
        , ldrStreakStats = toStreakStats stats
        }
  where
    toStreakStats :: DbStreak.StreakStatsRow -> StreakStats
    toStreakStats DbStreak.StreakStatsRow{..} = StreakStats
      { ssCurrent = fromIntegral ssrCurrent
      , ssAverage = ssrAverage
      , ssLongest = fromIntegral ssrLongest
      }

-- PUT /api/logs/:id
--
-- Rename-only vs structural edit: if the incoming `metrics` array has units
-- elementwise identical to the existing log's `metric_units`, we treat it as
-- a rename (always allowed). Otherwise it's a structural change, which is
-- only allowed when the log has no entries. The count-then-update dance
-- runs inside a single serializable transaction so a concurrent entry
-- insert can't slip in between the check and the update.
updateLogHandler :: AuthResult AuthUser -> Text -> UpdateLogRequest -> AppM LogResponse
updateLogHandler auth lid UpdateLogRequest{..} = do
  uid <- requireUser auth
  validateName ulrName
  -- Validate metrics shape outside the tx so we can 400 without a DB round-trip.
  case ulrMetrics of
    Just ms -> validateMetrics ms
    Nothing -> pure ()
  pool <- asks envDbPool

  let applyUpdate newNames newUnits = do
        mUpdated <- Tx.statement
                      (lid, uid, ulrName, ulrDescription, newNames, newUnits)
                      DbLog.updateLog
        pure (Right mUpdated)

  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mExisting <- Tx.statement (lid, uid) DbLog.getLog
      case mExisting of
        Nothing       -> pure (Left NotFound)
        Just existing -> do
          case ulrMetrics of
            Nothing ->
              applyUpdate (logMetricNames existing) (logMetricUnits existing)
            Just ms -> do
              let normed     = map normalizeMetric ms
                  incomingNm = V.fromList (map msName normed)
                  incomingUn = V.fromList (map msUnit normed)
                  unitsMatch = incomingUn == logMetricUnits existing
              if unitsMatch
                then applyUpdate incomingNm incomingUn
                else do
                  count <- Tx.statement lid DbLog.countLogEntries
                  if count == 0
                    then applyUpdate incomingNm incomingUn
                    else pure (Left (BadRequest "Cannot change metric structure of a log that has entries"))

  case result of
    Left _usageErr              -> throwError $ appErrorToServantErr (Internal "database error")
    Right (Left e)              -> throwError $ appErrorToServantErr e
    Right (Right Nothing)       -> throwError $ appErrorToServantErr NotFound
    Right (Right (Just l))      -> pure (toLogResponse l)

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
  , logrMetrics     = zipWith MetricSpec
                        (V.toList (logMetricNames l))
                        (V.toList (logMetricUnits l))
  , logrDescription = logDescription l
  , logrStartDate   = logStartDate l
  , logrCreatedAt   = logCreatedAt l
  , logrUpdatedAt   = logUpdatedAt l
  }

toEntryResponse :: Entry -> EntryResponse
toEntryResponse e = EntryResponse
  { erId        = entId e
  , erLogId     = entLogId e
  , erEntryDate = entDate e
  , erValues    = zipWith EntryValue
                    (V.toList (entQuantities e))
                    (V.toList (entDescriptions e))
  , erCreatedAt = entCreatedAt e
  , erUpdatedAt = entUpdatedAt e
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

normalizeMetric :: MetricSpec -> MetricSpec
normalizeMetric (MetricSpec n u) =
  MetricSpec (T.strip n) (normalizeUnit (T.strip u))

validateMetrics :: [MetricSpec] -> AppM ()
validateMetrics ms
  | null ms = throwError $ appErrorToServantErr
      (BadRequest "log must have at least one metric")
  | otherwise = mapM_ validateOne ms
  where
    validateOne (MetricSpec n u) = do
      when (T.null (T.strip n)) $
        throwError $ appErrorToServantErr (BadRequest "metric name cannot be empty")
      when (T.length n > 64) $
        throwError $ appErrorToServantErr (BadRequest "metric name too long (max 64)")
      validateUnit u
