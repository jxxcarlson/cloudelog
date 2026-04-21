module Api.Collections where

import Api.RequestTypes
import Data.Text (Text)
import Servant

type CollectionsAPI =
       -- GET /api/collections
       Get '[JSON] [CollectionSummaryResponse]
  :<|> -- POST /api/collections
       ReqBody '[JSON] CreateCollectionRequest :> Post '[JSON] CollectionResponse
  :<|> -- GET /api/collections/:id
       Capture "id" Text :> Get '[JSON] CollectionDetailResponse
  :<|> -- PUT /api/collections/:id
       Capture "id" Text
         :> ReqBody '[JSON] UpdateCollectionRequest
         :> Put '[JSON] CollectionResponse
  :<|> -- DELETE /api/collections/:id
       Capture "id" Text :> Verb 'DELETE 204 '[JSON] NoContent
  :<|> -- POST /api/collections/:id/entries  (combined-entry)
       Capture "id" Text :> "entries"
         :> ReqBody '[JSON] CombinedEntryRequest
         :> Post '[JSON] CollectionDetailResponse
