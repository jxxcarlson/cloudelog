module Db.Pool (createPool) where

import           Data.ByteString (ByteString)
import qualified Hasql.Pool      as Pool
import           Data.Time.Clock (DiffTime)

createPool :: ByteString -> IO Pool.Pool
createPool connSettings =
  Pool.acquire poolSize acquireTimeout idleTimeout maxLifetime connSettings
  where
    poolSize :: Int
    poolSize = 10
    acquireTimeout, idleTimeout, maxLifetime :: DiffTime
    acquireTimeout = 10
    idleTimeout    = 600
    maxLifetime    = 3600
