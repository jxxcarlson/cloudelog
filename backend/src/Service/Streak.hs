module Service.Streak (computeStreaks) where

import Data.Time.Calendar (Day, addDays)

-- | Given entries sorted by date ascending, produce one (start_date, length) tuple
--   per maximal run of consecutive dates with quantity > 0. A calendar gap or
--   a quantity <= 0 breaks the run.
computeStreaks :: [(Day, Double)] -> [(Day, Int)]
computeStreaks = go Nothing []
  where
    -- State: `cur` = Just (start, length) of the in-progress run, or Nothing.
    --        `acc` = finalized runs in reverse order.
    go :: Maybe (Day, Int) -> [(Day, Int)] -> [(Day, Double)] -> [(Day, Int)]
    go cur acc [] = reverse (maybe acc (: acc) cur)
    go cur acc ((d, q) : rest)
      | q > 0 = case cur of
          Nothing          -> go (Just (d, 1)) acc rest
          Just (s, n)
            | addDays (fromIntegral n) s == d -> go (Just (s, n + 1)) acc rest
            | otherwise                       -> go (Just (d, 1))     (flush cur acc) rest
      | otherwise = go Nothing (flush cur acc) rest

    flush Nothing  acc = acc
    flush (Just r) acc = r : acc
