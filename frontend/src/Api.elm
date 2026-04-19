module Api exposing
    ( ApiError
    , apiErrorToString
    , me
    , signup
    , login
    , logout
    , listLogs
    , createLog
    , getLog
    , updateLog
    , deleteLog
    , postEntry
    , updateEntry
    , deleteEntry
    , logDecoder
    , logSummaryDecoder
    , entryDecoder
    )

import Date exposing (Date)
import Http
import Iso8601
import Json.Decode as D
import Json.Encode as E
import Time exposing (Posix)
import Types exposing (Entry, Log, LogSummary, Unit(..), User, unitFromString, unitToString)


apiBase : String
apiBase =
    ""


type alias ApiError =
    Http.Error


apiErrorToString : Http.Error -> String
apiErrorToString err =
    case err of
        Http.BadUrl u ->
            "bad url: " ++ u

        Http.Timeout ->
            "request timed out"

        Http.NetworkError ->
            "network error — is the backend running on :8081?"

        Http.BadStatus 401 ->
            "not signed in"

        Http.BadStatus 403 ->
            "forbidden"

        Http.BadStatus 404 ->
            "not found"

        Http.BadStatus code ->
            "server error " ++ String.fromInt code

        Http.BadBody msg ->
            "bad response body: " ++ msg



---------------------------------------------------------------
-- request helper (cookies via riskyRequest)
---------------------------------------------------------------


cookieRequest :
    { method : String
    , url : String
    , body : Http.Body
    , expect : Http.Expect msg
    }
    -> Cmd msg
cookieRequest r =
    Http.riskyRequest
        { method = r.method
        , headers = []
        , url = r.url
        , body = r.body
        , expect = r.expect
        , timeout = Nothing
        , tracker = Nothing
        }



---------------------------------------------------------------
-- auth
---------------------------------------------------------------


me : (Result Http.Error User -> msg) -> Cmd msg
me toMsg =
    cookieRequest
        { method = "GET"
        , url = apiBase ++ "/api/auth/me"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg userDecoder
        }


signup : String -> String -> (Result Http.Error () -> msg) -> Cmd msg
signup email password toMsg =
    cookieRequest
        { method = "POST"
        , url = apiBase ++ "/api/auth/signup"
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "email", E.string email )
                    , ( "password", E.string password )
                    ]
        , expect = Http.expectWhatever toMsg
        }


login : String -> String -> (Result Http.Error () -> msg) -> Cmd msg
login email password toMsg =
    cookieRequest
        { method = "POST"
        , url = apiBase ++ "/api/auth/login"
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "email", E.string email )
                    , ( "password", E.string password )
                    ]
        , expect = Http.expectWhatever toMsg
        }


logout : (Result Http.Error () -> msg) -> Cmd msg
logout toMsg =
    cookieRequest
        { method = "POST"
        , url = apiBase ++ "/api/auth/logout"
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        }



---------------------------------------------------------------
-- logs
---------------------------------------------------------------


listLogs : (Result Http.Error (List LogSummary) -> msg) -> Cmd msg
listLogs toMsg =
    cookieRequest
        { method = "GET"
        , url = apiBase ++ "/api/logs"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg (D.list logSummaryDecoder)
        }


createLog : { name : String, unit : String, description : String } -> (Result Http.Error Log -> msg) -> Cmd msg
createLog { name, unit, description } toMsg =
    cookieRequest
        { method = "POST"
        , url = apiBase ++ "/api/logs"
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "name", E.string name )
                    , ( "unit", E.string unit )
                    , ( "description", E.string description )
                    ]
        , expect = Http.expectJson toMsg logDecoder
        }


getLog : String -> (Result Http.Error { log : Log, entries : List Entry } -> msg) -> Cmd msg
getLog logId toMsg =
    cookieRequest
        { method = "GET"
        , url = apiBase ++ "/api/logs/" ++ logId
        , body = Http.emptyBody
        , expect =
            Http.expectJson toMsg
                (D.map2 (\l es -> { log = l, entries = es })
                    (D.field "log" logDecoder)
                    (D.field "entries" (D.list entryDecoder))
                )
        }


updateLog :
    String
    -> { name : String, description : String, unit : Maybe String }
    -> (Result Http.Error Log -> msg)
    -> Cmd msg
updateLog logId { name, description, unit } toMsg =
    let
        base =
            [ ( "name", E.string name )
            , ( "description", E.string description )
            ]

        fields =
            case unit of
                Just u ->
                    base ++ [ ( "unit", E.string u ) ]

                Nothing ->
                    base
    in
    cookieRequest
        { method = "PUT"
        , url = apiBase ++ "/api/logs/" ++ logId
        , body = Http.jsonBody (E.object fields)
        , expect = Http.expectJson toMsg logDecoder
        }


deleteLog : String -> (Result Http.Error () -> msg) -> Cmd msg
deleteLog logId toMsg =
    cookieRequest
        { method = "DELETE"
        , url = apiBase ++ "/api/logs/" ++ logId
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        }



---------------------------------------------------------------
-- entries
---------------------------------------------------------------


postEntry :
    String
    -> { entryDate : Date, quantity : Float, description : String }
    -> (Result Http.Error (List Entry) -> msg)
    -> Cmd msg
postEntry logId { entryDate, quantity, description } toMsg =
    cookieRequest
        { method = "POST"
        , url = apiBase ++ "/api/logs/" ++ logId ++ "/entries"
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "entryDate", E.string (Date.toIsoString entryDate) )
                    , ( "quantity", E.float quantity )
                    , ( "description", E.string description )
                    ]
        , expect =
            Http.expectJson toMsg (D.field "entries" (D.list entryDecoder))
        }


updateEntry :
    String
    -> { quantity : Float, description : String }
    -> (Result Http.Error Entry -> msg)
    -> Cmd msg
updateEntry entryId { quantity, description } toMsg =
    cookieRequest
        { method = "PUT"
        , url = apiBase ++ "/api/entries/" ++ entryId
        , body =
            Http.jsonBody <|
                E.object
                    [ ( "quantity", E.float quantity )
                    , ( "description", E.string description )
                    ]
        , expect = Http.expectJson toMsg entryDecoder
        }


deleteEntry : String -> (Result Http.Error () -> msg) -> Cmd msg
deleteEntry entryId toMsg =
    cookieRequest
        { method = "DELETE"
        , url = apiBase ++ "/api/entries/" ++ entryId
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        }



---------------------------------------------------------------
-- decoders
---------------------------------------------------------------


userDecoder : D.Decoder User
userDecoder =
    D.map2 User
        (D.field "id" D.string)
        (D.field "email" D.string)


unitDecoder : D.Decoder Unit
unitDecoder =
    D.map unitFromString D.string


logDecoder : D.Decoder Log
logDecoder =
    D.map6 Log
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "unit" unitDecoder)
        (D.field "description" D.string)
        (D.field "createdAt" Iso8601.decoder)
        (D.field "updatedAt" Iso8601.decoder)


logSummaryDecoder : D.Decoder LogSummary
logSummaryDecoder =
    D.map6 LogSummary
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "unit" unitDecoder)
        (D.field "description" D.string)
        (D.field "createdAt" Iso8601.decoder)
        (D.field "updatedAt" Iso8601.decoder)


entryDecoder : D.Decoder Entry
entryDecoder =
    D.map5 Entry
        (D.field "id" D.string)
        (D.field "logId" D.string)
        (D.field "entryDate" dateDecoder)
        (D.field "quantity" D.float)
        (D.field "description" D.string)


dateDecoder : D.Decoder Date
dateDecoder =
    D.string
        |> D.andThen
            (\s ->
                case Date.fromIsoString s of
                    Ok d ->
                        D.succeed d

                    Err msg ->
                        D.fail ("invalid date: " ++ msg)
            )
