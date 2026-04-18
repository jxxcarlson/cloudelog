module Api.Types where

import Api.Auth (AuthAPI)
import Api.Logs (LogsAPI, EntriesAPI)
import Servant
import Servant.Auth.Server (Auth, Cookie)
import Service.Auth        (AuthUser)

type CloudelogAPI =
       "api" :> "auth"    :> AuthAPI
  :<|> "api" :> "logs"    :> Auth '[Cookie] AuthUser :> LogsAPI
  :<|> "api" :> "entries" :> Auth '[Cookie] AuthUser :> EntriesAPI
  :<|> "api" :> "health"  :> Get '[JSON] String
