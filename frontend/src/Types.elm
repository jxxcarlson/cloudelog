module Types exposing
    ( User
    , Log
    , LogSummary
    , Entry
    , EntryValue
    , Metric
    , StreakStats
    , Collection
    , CollectionSummary
    , CollectionMember
    , CollectionDetail
    , CombinedTotal
    , Device(..)
    , classify
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
    , collectionId : Maybe String
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias Log =
    { id : String
    , name : String
    , metrics : List Metric
    , description : String
    , startDate : Date
    , collectionId : Maybe String
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


type alias Collection =
    { id : String
    , name : String
    , description : String
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias CollectionSummary =
    { id : String
    , name : String
    , description : String
    , memberCount : Int
    , createdAt : Posix
    , updatedAt : Posix
    }


type alias CollectionMember =
    { log : Log
    , entries : List Entry
    , streakStats : StreakStats
    }


type alias CollectionDetail =
    { collection : Collection
    , members : List CollectionMember
    }


type alias CombinedTotal =
    { unit : String
    , total : Float
    , average : Maybe Float
    , days : Int
    , skipped : Int
    , currentStreak : Int
    , longestStreak : Int
    , contributors : Int
    }


type Device
    = Phone
    | Desktop


classify : Int -> Device
classify widthPx =
    if widthPx < 600 then
        Phone

    else
        Desktop
