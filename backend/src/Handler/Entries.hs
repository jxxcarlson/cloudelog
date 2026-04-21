module Handler.Entries
  ( postEntryHandler
  , updateEntryHandler
  , deleteEntryHandler
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Entry                as DbEntry
import qualified Db.Streak               as DbStreak
import           Handler.Logs            (requireUser, toEntryResponse)
import           Control.Monad           (when)
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Int                (Int32)
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.UUID               (toText)
import qualified Data.UUID.V4            as UUID
import qualified Data.Vector             as V
import qualified Hasql.Pool              as Pool
import qualified Hasql.Transaction       as Tx
import qualified Hasql.Transaction.Sessions as Tx
import qualified Hasql.Session           as Session
import           Servant                 (NoContent(..))
import           Servant.Auth.Server     (AuthResult)
import           Service.Auth            (AuthUser)
import           Service.SkipFill        (datesToFill)
import qualified Service.Streak          as Streak
import           Types.Common            (LogId)
import           Types.Entry             (Entry(..))

-- POST /api/logs/:id/entries
-- Preflight: read maxDate to know how many UUIDs to pre-generate for skip-fills.
-- Then in one transaction: FOR UPDATE lock, recompute dates (cheap), bulk insert
-- skips (ON CONFLICT DO NOTHING — safe if maxDate moved forward between preflight
-- and transaction), upsert the main entry, return full list.
postEntryHandler
  :: AuthResult AuthUser -> Text -> CreateEntryRequest
  -> AppM EntriesListResponse
postEntryHandler auth lid CreateEntryRequest{..} = do
  uid <- requireUser auth
  mapM_ (validateQuantity . evQuantity) cerValues
  pool <- asks envDbPool

  -- Ingress length check: we need the metric count from the log before we
  -- can validate values.length. Read it outside the tx for a clean 400.
  rCount <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.getLogMetricCount
  mCount0 <- case rCount of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right n -> pure (fromIntegral n :: Int)
  when (length cerValues /= mCount0) $
    throwError $ appErrorToServantErr
      (BadRequest $ T.pack $ "values must have " <> show mCount0
                          <> " entries (got " <> show (length cerValues) <> ")")

  -- Preflight: compute worst-case number of skip IDs needed.
  preflight <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.maxEntryDate
  mLast <- case preflight of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right m -> pure m
  let preFillDays = datesToFill mLast cerEntryDate
  preFillIds <- liftIO $ generateUuids (length preFillDays)

  newEntryId <- liftIO $ toText <$> UUID.nextRandom

  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mUserId <- Tx.statement lid DbEntry.lockLogForUpdate
      case mUserId of
        Nothing        -> pure (Left NotFound)
        Just ownerId
          | ownerId /= uid -> pure (Left Forbidden)
          | otherwise      -> do
              mCount <- Tx.statement lid DbEntry.getLogMetricCount
              -- length check already validated at ingress
              _ <- if null preFillDays
                     then pure ()
                     else Tx.statement
                            ( lid
                            , V.fromList preFillIds
                            , V.fromList preFillDays
                            , mCount
                            )
                            DbEntry.insertSkipFills
              let qs    = V.fromList (map evQuantity cerValues)
                  descs = V.fromList (map evDescription cerValues)
              _entry <- Tx.statement
                          (newEntryId, lid, cerEntryDate, qs, descs)
                          DbEntry.upsertEntry
              recomputeStreaksTx lid
              allEntries <- Tx.statement lid DbEntry.listEntriesByLog
              pure (Right allEntries)

  case result of
    Left _usageErr      -> throwError $ appErrorToServantErr (Internal "database error")
    Right (Left e)      -> throwError $ appErrorToServantErr e
    Right (Right vec)   -> pure EntriesListResponse
                             { elrEntries = map toEntryResponse (V.toList vec) }

-- PUT /api/entries/:id
updateEntryHandler :: AuthResult AuthUser -> Text -> UpdateEntryRequest -> AppM EntryResponse
updateEntryHandler auth eid UpdateEntryRequest{..} = do
  uid <- requireUser auth
  mapM_ (validateQuantity . evQuantity) uerValues
  pool <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mCurrent <- Tx.statement (eid, uid) DbEntry.selectEntryForOwner
      case mCurrent of
        Nothing -> pure (Right Nothing)
        Just e  -> do
          let expected = V.length (entQuantities e)
          if length uerValues /= expected
            then pure (Left expected)
            else do
              let qs    = V.fromList (map evQuantity uerValues)
                  descs = V.fromList (map evDescription uerValues)
              mUpdated <- Tx.statement (eid, uid, qs, descs) DbEntry.updateEntry
              case mUpdated of
                Nothing -> pure (Right Nothing)
                Just e' -> do
                  recomputeStreaksTx (entLogId e')
                  pure (Right (Just e'))
  case result of
    Left _             -> throwError $ appErrorToServantErr (Internal "database error")
    Right (Left n)     -> throwError $ appErrorToServantErr
                            (BadRequest $ T.pack $ "values must have " <> show n
                                                <> " entries (got " <> show (length uerValues) <> ")")
    Right (Right Nothing)  -> throwError $ appErrorToServantErr NotFound
    Right (Right (Just e)) -> pure (toEntryResponse e)

-- DELETE /api/entries/:id
deleteEntryHandler :: AuthResult AuthUser -> Text -> AppM NoContent
deleteEntryHandler auth eid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mLid <- Tx.statement (eid, uid) DbEntry.deleteEntry
      case mLid of
        Nothing  -> pure Nothing
        Just lid -> do
          recomputeStreaksTx lid
          pure (Just ())
  case result of
    Left _        -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing -> throwError $ appErrorToServantErr NotFound
    Right _       -> pure NoContent

---------------------------------------------------------------
-- helpers
---------------------------------------------------------------

generateUuids :: Int -> IO [Text]
generateUuids n
  | n <= 0    = pure []
  | otherwise = mapM (\_ -> toText <$> UUID.nextRandom) [1..n]

-- | Recompute and persist streaks for @lid@. Call inside the same transaction
--   as any entry mutation so the streaks table stays in lockstep with entries.
recomputeStreaksTx :: LogId -> Tx.Transaction ()
recomputeStreaksTx lid = do
  rows <- V.toList <$> Tx.statement lid DbStreak.selectEntryDateQuantity
  let pairs      = map (\(d, qs) -> (d, V.toList qs)) rows
      streaks    = Streak.computeStreaks pairs
      toInt32 n  = fromIntegral n :: Int32
      dates      = V.fromList (map fst streaks)
      lengths    = V.fromList (map (toInt32 . snd) streaks)
  Tx.statement lid DbStreak.deleteStreaksForLog
  if V.null dates
    then pure ()
    else Tx.statement (lid, dates, lengths) DbStreak.bulkInsertStreaks

validateQuantity :: Double -> AppM ()
validateQuantity q
  | isNaN q || isInfinite q =
      throwError $ appErrorToServantErr (BadRequest "quantity must be a finite number")
  | q < 0 =
      throwError $ appErrorToServantErr (BadRequest "quantity cannot be negative")
  | otherwise = pure ()
