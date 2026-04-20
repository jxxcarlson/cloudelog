module Db.Streak
  ( selectEntryDateQuantity
  , deleteStreaksForLog
  , bulkInsertStreaks
  , selectStreakStats
  , StreakStatsRow(..)
  ) where

import           Data.Functor.Contravariant ((>$<))
import           Data.Int                   (Int32)
import           Data.Time.Calendar         (Day)
import           Data.Vector                (Vector)
import qualified Data.Vector                as V
import qualified Hasql.Decoders             as D
import qualified Hasql.Encoders             as E
import           Hasql.Statement            (Statement(..))
import           Types.Common               (LogId)

-- | All entries for a log, returned as (entry_date, quantities) in ascending date order.
--   Feeds Service.Streak.computeStreaks.
selectEntryDateQuantity :: Statement LogId (Vector (Day, Vector Double))
selectEntryDateQuantity = Statement sql encoder decoder True
  where
    sql =
      "SELECT entry_date, quantities FROM entries \
      \WHERE log_id = $1 ORDER BY entry_date ASC"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.rowVector $
      (,) <$> D.column (D.nonNullable D.date)
          <*> D.column (D.nonNullable doubleArrayD)

doubleArrayD :: D.Value (Vector Double)
doubleArrayD = D.array (D.dimension V.replicateM (D.element (D.nonNullable D.float8)))

deleteStreaksForLog :: Statement LogId ()
deleteStreaksForLog = Statement sql encoder D.noResult True
  where
    sql     = "DELETE FROM streaks WHERE log_id = $1"
    encoder = E.param (E.nonNullable E.text)

-- | Bulk insert streaks. Params: (log_id, start_dates[], lengths[]).
--   The two arrays are paired element-wise via unnest.
bulkInsertStreaks :: Statement (LogId, Vector Day, Vector Int32) ()
bulkInsertStreaks = Statement sql encoder D.noResult True
  where
    sql =
      "INSERT INTO streaks (log_id, start_date, length) \
      \SELECT $1, unnest($2 :: date[]), unnest($3 :: int[])"
    encoder =
      ((\(a,_,_) -> a) >$< E.param (E.nonNullable E.text)) <>
      ((\(_,b,_) -> b) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.date)))))) <>
      ((\(_,_,c) -> c) >$< E.param (E.nonNullable
          (E.array (E.dimension foldl (E.element (E.nonNullable E.int4))))))

-- | Three streak aggregates in one round-trip.
--   current = length of the most-recent streak (by start_date), 0 if none.
--   average = arithmetic mean of all streak lengths, NULL if none.
--   longest = max streak length, 0 if none.
data StreakStatsRow = StreakStatsRow
  { ssrCurrent :: Int32
  , ssrAverage :: Maybe Double
  , ssrLongest :: Int32
  } deriving (Show, Eq)

selectStreakStats :: Statement LogId StreakStatsRow
selectStreakStats = Statement sql encoder decoder True
  where
    sql =
      "SELECT \
      \  COALESCE((SELECT length FROM streaks WHERE log_id = $1 \
      \            ORDER BY start_date DESC LIMIT 1), 0)        AS current_, \
      \  (SELECT AVG(length)::double precision FROM streaks \
      \   WHERE log_id = $1)                                    AS avg_, \
      \  COALESCE((SELECT MAX(length) FROM streaks WHERE log_id = $1), 0) AS longest_"
    encoder = E.param (E.nonNullable E.text)
    decoder = D.singleRow $
      StreakStatsRow
        <$> D.column (D.nonNullable D.int4)
        <*> D.column (D.nullable    D.float8)
        <*> D.column (D.nonNullable D.int4)
