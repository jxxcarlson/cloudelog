module Types exposing
    ( User
    , Log
    , LogSummary
    , Entry
    , EntryValue
    , Metric
    , StreakStats
    )

import Date exposing (Date)
import Time exposing (Posix)


type alias User =
    { id : String
    , email : String
    }


type alias Metric =
    { name : String
    , unit : String
    }


type alias LogSummary =
    { id : String
    , name : String
    , metrics : List Metric
    , description : String
    , startDate : Date
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias Log =
    { id : String
    , name : String
    , metrics : List Metric
    , description : String
    , startDate : Date
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias EntryValue =
    { quantity : Float
    , description : String
    }


type alias Entry =
    { id : String
    , logId : String
    , date : Date
    , values : List EntryValue
    }


type alias StreakStats =
    { current : Int
    , average : Maybe Float
    , longest : Int
    }
