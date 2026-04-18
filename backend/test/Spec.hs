module Main where

import Test.Hspec

main :: IO ()
main = hspec $ describe "bootstrap" $
  it "runs" $ True `shouldBe` True
