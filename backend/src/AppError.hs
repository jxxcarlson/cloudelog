module AppError
  ( AppError(..)
  , appErrorToServantErr
  ) where

import           Data.Aeson            (object, (.=))
import qualified Data.Aeson            as Aeson
import           Data.Text             (Text)
import           Servant               (ServerError(..), err400, err401, err403, err404, err409, err500)

data AppError
  = NotFound
  | Forbidden
  | Unauthorized
  | BadRequest Text
  | Conflict Text
  | Internal Text
  deriving (Show, Eq)

appErrorToServantErr :: AppError -> ServerError
appErrorToServantErr e =
  let (base, tag, msg) = case e of
        NotFound      -> (err404, "not_found"   :: Text, "not found")
        Forbidden     -> (err403, "forbidden"   :: Text, "forbidden")
        Unauthorized  -> (err401, "unauthorized":: Text, "unauthorized")
        BadRequest m  -> (err400, "bad_request" :: Text, m)
        Conflict m    -> (err409, "conflict"    :: Text, m)
        Internal m    -> (err500, "internal"    :: Text, m)
  in base
     { errBody    = Aeson.encode $ object ["error" .= tag, "message" .= msg]
     , errHeaders = [("Content-Type", "application/json")]
     }
