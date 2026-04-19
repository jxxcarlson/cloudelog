module Route exposing (Route(..), fromUrl, toString)

import Url exposing (Url)
import Url.Parser as P exposing ((</>), Parser, oneOf, s, string)


type Route
    = Home
    | Login
    | Signup
    | LogDetail String
    | NotFound


parser : Parser (Route -> a) a
parser =
    oneOf
        [ P.map Home P.top
        , P.map Login (s "login")
        , P.map Signup (s "signup")
        , P.map LogDetail (s "logs" </> string)
        ]


fromUrl : Url -> Route
fromUrl url =
    Maybe.withDefault NotFound (P.parse parser url)


toString : Route -> String
toString r =
    case r of
        Home ->
            "/"

        Login ->
            "/login"

        Signup ->
            "/signup"

        LogDetail id ->
            "/logs/" ++ id

        NotFound ->
            "/"
