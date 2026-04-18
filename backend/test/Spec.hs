module Main where

import           Test.Hspec
import qualified Service.SkipFillSpec

main :: IO ()
main = hspec $ do
  describe "Service.SkipFill" Service.SkipFillSpec.spec
