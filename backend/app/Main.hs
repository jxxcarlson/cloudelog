module Main where

import App    (startApp)
import Config (loadConfig)

main :: IO ()
main = loadConfig >>= startApp
