module Main where

import           Test.Hspec
import qualified Service.SkipFillSpec
import qualified Service.StreakSpec

main :: IO ()
main = hspec $ do
  describe "Service.SkipFill" Service.SkipFillSpec.spec
  describe "Service.Streak"   Service.StreakSpec.spec
