module Service.SkipFill (datesToFill) where

import Data.Time.Calendar (Day, addDays, diffDays)

-- | Dates strictly between @lastDate@ and @newDate@, inclusive of neither endpoint.
--   Returns [] if there is no prior entry (@Nothing@) or the new entry is not
--   strictly after the last entry (same-day, consecutive, or back-fill).
datesToFill :: Maybe Day -> Day -> [Day]
datesToFill Nothing       _        = []
datesToFill (Just lastD)  newD
  | newD <= addDays 1 lastD = []
  | otherwise               =
      let n = diffDays newD lastD  -- e.g. 3 means last..last+3 → fill [last+1, last+2]
      in  map (`addDays` lastD) [1 .. n - 1]
