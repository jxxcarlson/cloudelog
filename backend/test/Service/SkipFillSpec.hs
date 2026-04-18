module Service.SkipFillSpec (spec) where

import           Data.Time.Calendar (fromGregorian)
import qualified Service.SkipFill   as SkipFill
import           Test.Hspec

spec :: Spec
spec = describe "Service.SkipFill.datesToFill" $ do

  it "first-ever entry: no last date, returns []" $
    SkipFill.datesToFill Nothing (fromGregorian 2026 4 18) `shouldBe` []

  it "same day as last entry: returns []" $
    SkipFill.datesToFill (Just (fromGregorian 2026 4 18)) (fromGregorian 2026 4 18) `shouldBe` []

  it "consecutive day: returns []" $
    SkipFill.datesToFill (Just (fromGregorian 2026 4 17)) (fromGregorian 2026 4 18) `shouldBe` []

  it "one-day gap: returns one date" $
    SkipFill.datesToFill (Just (fromGregorian 2026 4 16)) (fromGregorian 2026 4 18)
      `shouldBe` [fromGregorian 2026 4 17]

  it "multi-day gap: returns all dates strictly between" $
    SkipFill.datesToFill (Just (fromGregorian 2026 4 10)) (fromGregorian 2026 4 15)
      `shouldBe` map (fromGregorian 2026 4) [11, 12, 13, 14]

  it "back-fill (new date < last date): returns []" $
    SkipFill.datesToFill (Just (fromGregorian 2026 4 18)) (fromGregorian 2026 4 10) `shouldBe` []

  it "crosses month boundary correctly" $
    SkipFill.datesToFill (Just (fromGregorian 2026 3 30)) (fromGregorian 2026 4 2)
      `shouldBe` [fromGregorian 2026 3 31, fromGregorian 2026 4 1]
