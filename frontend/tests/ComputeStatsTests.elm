module ComputeStatsTests exposing (suite)

import Date exposing (fromRataDie)
import Expect
import LogView exposing (computeStats)
import Test exposing (Test, describe, test)
import Time
import Types exposing (Entry, Log, Metric)


mkLog : List Metric -> Log
mkLog metrics =
    { id = "log"
    , name = "Test"
    , metrics = metrics
    , description = ""
    , startDate = fromRataDie 1
    , collectionId = Nothing
    , createdAt = Time.millisToPosix 0
    , updatedAt = Time.millisToPosix 0
    }


mkEntry : Int -> List Float -> Entry
mkEntry rd qs =
    { id = "e" ++ String.fromInt rd
    , logId = "log"
    , date = fromRataDie rd
    , values = List.map (\q -> { quantity = q, description = "" }) qs
    }


suite : Test
suite =
    describe "LogView.computeStats"
        [ test "empty entries with a single-metric log: zero days, zero skipped, zero-row perMetric" <|
            \_ ->
                computeStats
                    (Just (mkLog [ { name = "miles", unit = "mi" } ]))
                    []
                    (fromRataDie 1)
                    |> Expect.equal
                        { days = 0
                        , skipped = 0
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 0, average = Nothing } ]
                        }
        , test "empty entries with no log: zero days, zero skipped, empty perMetric" <|
            \_ ->
                computeStats Nothing [] (fromRataDie 1)
                    |> Expect.equal { days = 0, skipped = 0, perMetric = [] }
        , test "single-metric: total and average over active entries, skip counted" <|
            \_ ->
                let
                    log =
                        mkLog [ { name = "miles", unit = "mi" } ]

                    entries =
                        [ mkEntry 100 [ 20 ]
                        , mkEntry 101 [ 0 ]
                        , mkEntry 102 [ 40 ]
                        ]
                in
                computeStats (Just log) entries (fromRataDie 102)
                    |> Expect.equal
                        { days = 3
                        , skipped = 1
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 60, average = Just 30 } ]
                        }
        , test "all-zero entry is treated as skipped (multi-metric)" <|
            \_ ->
                let
                    log =
                        mkLog
                            [ { name = "miles", unit = "mi" }
                            , { name = "minutes", unit = "min" }
                            ]

                    entries =
                        [ mkEntry 200 [ 0, 0 ]
                        , mkEntry 201 [ 3, 30 ]
                        ]
                in
                computeStats (Just log) entries (fromRataDie 201)
                    |> Expect.equal
                        { days = 2
                        , skipped = 1
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 3, average = Just 3 }
                            , { name = "minutes", unit = "min", total = 30, average = Just 30 }
                            ]
                        }
        , test "multi-metric: parallel totals and averages per position" <|
            \_ ->
                let
                    log =
                        mkLog
                            [ { name = "miles", unit = "mi" }
                            , { name = "minutes", unit = "min" }
                            ]

                    entries =
                        [ mkEntry 300 [ 2, 20 ]
                        , mkEntry 301 [ 4, 40 ]
                        , mkEntry 302 [ 6, 60 ]
                        ]
                in
                computeStats (Just log) entries (fromRataDie 302)
                    |> Expect.equal
                        { days = 3
                        , skipped = 0
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 12, average = Just 4 }
                            , { name = "minutes", unit = "min", total = 120, average = Just 40 }
                            ]
                        }
        , test "defensive: missing metric position is skipped (not counted) when an entry is short" <|
            \_ ->
                let
                    log =
                        mkLog
                            [ { name = "miles", unit = "mi" }
                            , { name = "minutes", unit = "min" }
                            , { name = "feet", unit = "ft" }
                            ]

                    entries =
                        [ mkEntry 400 [ 2, 20 ] -- short: only two values, missing feet
                        , mkEntry 401 [ 4, 40, 100 ]
                        ]
                in
                computeStats (Just log) entries (fromRataDie 401)
                    |> Expect.equal
                        { days = 2
                        , skipped = 0
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 6, average = Just 3 }
                            , { name = "minutes", unit = "min", total = 60, average = Just 30 }
                            , { name = "feet", unit = "ft", total = 100, average = Just 100 }
                            ]
                        }
        , test "all skips: averages are Nothing" <|
            \_ ->
                let
                    log =
                        mkLog [ { name = "miles", unit = "mi" } ]

                    entries =
                        [ mkEntry 500 [ 0 ]
                        , mkEntry 501 [ 0 ]
                        ]
                in
                computeStats (Just log) entries (fromRataDie 501)
                    |> Expect.equal
                        { days = 2
                        , skipped = 2
                        , perMetric =
                            [ { name = "miles", unit = "mi", total = 0, average = Nothing } ]
                        }
        ]
