module Service.Streak (computeStreaks, anyPositive) where

import Data.Time.Calendar (Day, addDays)

-- | True if at least one element of the list is > 0.
anyPositive :: [Double] -> Bool
anyPositive = any (> 0)

-- | Given entries sorted by date ascending, produce one (start_date, length)
--   tuple per maximal run of consecutive dates with *any* quantity > 0.
--   A calendar gap or an all-zero day breaks the run.
computeStreaks :: [(Day, [Double])] -> [(Day, Int)]
computeStreaks = go Nothing []
  where
    go :: Maybe (Day, Int) -> [(Day, Int)] -> [(Day, [Double])] -> [(Day, Int)]
    go cur acc [] = reverse (maybe acc (: acc) cur)
    go cur acc ((d, qs) : rest)
      | anyPositive qs = case cur of
          Nothing          -> go (Just (d, 1)) acc rest
          Just (s, n)
            | addDays (fromIntegral n) s == d -> go (Just (s, n + 1)) acc rest
            | otherwise                       -> go (Just (d, 1))     (flush cur acc) rest
      | otherwise = go Nothing (flush cur acc) rest

    flush Nothing  acc = acc
    flush (Just r) acc = r : acc
