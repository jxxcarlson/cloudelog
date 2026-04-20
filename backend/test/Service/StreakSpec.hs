module Service.StreakSpec (spec) where

import           Data.Time.Calendar (fromGregorian)
import qualified Service.Streak     as Streak
import           Test.Hspec

spec :: Spec
spec = describe "Service.Streak.computeStreaks" $ do

  it "empty list: no streaks" $
    Streak.computeStreaks [] `shouldBe` []

  it "all-zero entries: no streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 0)
      , (fromGregorian 2026 4 2, 0)
      , (fromGregorian 2026 4 3, 0)
      ] `shouldBe` []

  it "single qty>0 entry: one streak of length 1" $
    Streak.computeStreaks [(fromGregorian 2026 4 1, 3.5)]
      `shouldBe` [(fromGregorian 2026 4 1, 1)]

  it "uninterrupted 5-day run: one streak of length 5" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 3, 1)
      , (fromGregorian 2026 4 4, 1)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe` [(fromGregorian 2026 4 1, 5)]

  it "run broken by quantity=0: two streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 3, 0)
      , (fromGregorian 2026 4 4, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 2)
        , (fromGregorian 2026 4 4, 1)
        ]

  it "run with a calendar gap (missing date): two streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 1)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 2)
        , (fromGregorian 2026 4 5, 1)
        ]

  it "alternating qty>0 / qty=0: many length-1 streaks" $
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, 0)
      , (fromGregorian 2026 4 3, 1)
      , (fromGregorian 2026 4 4, 0)
      , (fromGregorian 2026 4 5, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 1)
        , (fromGregorian 2026 4 3, 1)
        , (fromGregorian 2026 4 5, 1)
        ]

  it "negative quantity: treated like zero (breaks the streak)" $
    -- Guards against accidental regressions if handler validation ever misses a negative.
    Streak.computeStreaks
      [ (fromGregorian 2026 4 1, 1)
      , (fromGregorian 2026 4 2, -1)
      , (fromGregorian 2026 4 3, 1)
      ] `shouldBe`
        [ (fromGregorian 2026 4 1, 1)
        , (fromGregorian 2026 4 3, 1)
        ]
