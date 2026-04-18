module Api.Logs where

import Api.RequestTypes
import Data.Text (Text)
import Servant

type LogsAPI =
       -- GET /api/logs
       Get '[JSON] [LogResponse]
  :<|> -- POST /api/logs
       ReqBody '[JSON] CreateLogRequest :> Post '[JSON] LogResponse
  :<|> -- GET /api/logs/:id
       Capture "id" Text :> Get '[JSON] LogDetailResponse
  :<|> -- PUT /api/logs/:id
       Capture "id" Text :> ReqBody '[JSON] UpdateLogRequest :> Put '[JSON] LogResponse
  :<|> -- DELETE /api/logs/:id
       Capture "id" Text :> Verb 'DELETE 204 '[JSON] NoContent
  :<|> -- POST /api/logs/:id/entries  → skip-fill + accumulate; returns full entry list
       Capture "id" Text :> "entries"
         :> ReqBody '[JSON] CreateEntryRequest
         :> Post '[JSON] EntriesListResponse

type EntriesAPI =
       -- PUT /api/entries/:id
       Capture "id" Text :> ReqBody '[JSON] UpdateEntryRequest :> Put '[JSON] EntryResponse
  :<|> -- DELETE /api/entries/:id
       Capture "id" Text :> Verb 'DELETE 204 '[JSON] NoContent
