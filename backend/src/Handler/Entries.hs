module Handler.Entries
  ( postEntryHandler
  , updateEntryHandler
  , deleteEntryHandler
  ) where

import           Api.RequestTypes
import           AppEnv                  (AppEnv(..), AppM)
import           AppError                (AppError(..), appErrorToServantErr)
import qualified Db.Entry                as DbEntry
import           Handler.Logs            (requireUser, toEntryResponse)
import           Control.Monad.IO.Class  (liftIO)
import           Control.Monad.Reader    (asks)
import           Control.Monad.Except    (throwError)
import           Data.Maybe              (fromMaybe)
import           Data.Text               (Text)
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
  validateQuantity cerQuantity
  pool <- asks envDbPool

  -- Preflight: compute worst-case number of skip IDs needed.
  preflight <- liftIO $ Pool.use pool $ Session.statement lid DbEntry.maxEntryDate
  mLast <- case preflight of
    Left _  -> throwError $ appErrorToServantErr (Internal "database error")
    Right m -> pure m
  let preFillDays = datesToFill mLast cerEntryDate
  preFillIds <- liftIO $ generateUuids (length preFillDays)

  newEntryId <- liftIO $ toText <$> UUID.nextRandom
  let desc = fromMaybe "" cerDescription

  result <- liftIO $ Pool.use pool $
    Tx.transaction Tx.Serializable Tx.Write $ do
      mUserId <- Tx.statement lid DbEntry.lockLogForUpdate
      case mUserId of
        Nothing        -> pure (Left NotFound)
        Just ownerId
          | ownerId /= uid -> pure (Left Forbidden)
          | otherwise      -> do
              -- Inside the lock, use the preflight values. If the actual
              -- maxDate advanced in the interim, ON CONFLICT DO NOTHING handles it.
              _ <- if null preFillDays
                     then pure ()
                     else Tx.statement (lid, V.fromList preFillIds, V.fromList preFillDays)
                                       DbEntry.insertSkipFills
              _entry <- Tx.statement
                          (newEntryId, lid, cerEntryDate, cerQuantity, desc)
                          DbEntry.upsertEntry
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
  validateQuantity uerQuantity
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $
         Session.statement (eid, uid, uerQuantity, uerDescription) DbEntry.updateEntry
  case r of
    Left _          -> throwError $ appErrorToServantErr (Internal "database error")
    Right Nothing   -> throwError $ appErrorToServantErr NotFound
    Right (Just e)  -> pure (toEntryResponse e)

-- DELETE /api/entries/:id
deleteEntryHandler :: AuthResult AuthUser -> Text -> AppM NoContent
deleteEntryHandler auth eid = do
  uid  <- requireUser auth
  pool <- asks envDbPool
  r <- liftIO $ Pool.use pool $ Session.statement (eid, uid) DbEntry.deleteEntry
  case r of
    Left _   -> throwError $ appErrorToServantErr (Internal "database error")
    Right 0  -> throwError $ appErrorToServantErr NotFound
    Right _  -> pure NoContent

---------------------------------------------------------------
-- helpers
---------------------------------------------------------------

generateUuids :: Int -> IO [Text]
generateUuids n
  | n <= 0    = pure []
  | otherwise = mapM (\_ -> toText <$> UUID.nextRandom) [1..n]

validateQuantity :: Double -> AppM ()
validateQuantity q
  | isNaN q || isInfinite q =
      throwError $ appErrorToServantErr (BadRequest "quantity must be a finite number")
  | q < 0 =
      throwError $ appErrorToServantErr (BadRequest "quantity cannot be negative")
  | otherwise = pure ()
