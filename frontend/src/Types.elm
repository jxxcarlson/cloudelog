module Types exposing
    ( User
    , Log
    , LogSummary
    , Entry
    , Unit(..)
    , unitToString
    , unitFromString
    )

import Date exposing (Date)
import Time exposing (Posix)


type alias User =
    { id : String
    , email : String
    }


type alias LogSummary =
    { id : String
    , name : String
    , unit : Unit
    , description : String
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias Log =
    { id : String
    , name : String
    , unit : Unit
    , description : String
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias Entry =
    { id : String
    , logId : String
    , date : Date
    , quantity : Float
    , description : String
    }


type Unit
    = Minutes
    | Hours
    | Kilometers
    | Miles
    | Custom String


unitToString : Unit -> String
unitToString u =
    case u of
        Minutes ->
            "minutes"

        Hours ->
            "hours"

        Kilometers ->
            "kilometers"

        Miles ->
            "miles"

        Custom s ->
            s


unitFromString : String -> Unit
unitFromString raw =
    case String.toLower raw of
        "minutes" ->
            Minutes

        "hours" ->
            Hours

        "kilometers" ->
            Kilometers

        "miles" ->
            Miles

        _ ->
            Custom raw
