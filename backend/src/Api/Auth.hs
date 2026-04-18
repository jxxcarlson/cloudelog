module Api.Auth where

import Api.RequestTypes
import Servant
import Servant.Auth.Server (Auth, Cookie, SetCookie)
import Service.Auth         (AuthUser)

-- The two Set-Cookie headers Servant.Auth.Server emits (session JWT + XSRF).
type SetCookies a =
  Headers '[ Header "Set-Cookie" SetCookie
           , Header "Set-Cookie" SetCookie ] a

type AuthAPI =
       "signup"
         :> ReqBody '[JSON] SignupRequest
         :> Verb 'POST 204 '[JSON] (SetCookies NoContent)
  :<|> "login"
         :> ReqBody '[JSON] LoginRequest
         :> Verb 'POST 204 '[JSON] (SetCookies NoContent)
  :<|> "logout"
         :> Verb 'POST 204 '[JSON] (SetCookies NoContent)
  :<|> "me"
         :> Auth '[Cookie] AuthUser
         :> Get '[JSON] UserResponse
