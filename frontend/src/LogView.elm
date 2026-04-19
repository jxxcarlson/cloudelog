module LogView exposing (Stats, computeStats)

import Date exposing (Date)
import Types exposing (Entry)


type alias Stats =
    { days : Int
    , skipped : Int
    , total : Float
    , average : Maybe Float
    }


computeStats : List Entry -> Date -> Stats
computeStats entries today =
    case List.sortBy (Date.toRataDie << .date) entries of
        [] ->
            { days = 0, skipped = 0, total = 0, average = Nothing }

        first :: _ ->
            let
                days =
                    Date.diff Date.Days first.date today + 1

                skipped =
                    List.length (List.filter (\en -> en.quantity == 0) entries)

                total =
                    List.sum (List.map .quantity entries)

                active =
                    List.length (List.filter (\en -> en.quantity /= 0) entries)

                average =
                    if active > 0 then
                        Just (total / toFloat active)

                    else
                        Nothing
            in
            { days = days, skipped = skipped, total = total, average = average }
