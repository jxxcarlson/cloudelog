module CombinedTotalsTests exposing (suite)

import Collection
import Date exposing (fromRataDie)
import Expect
import Test exposing (Test, describe, test)
import Time
import Types exposing (CollectionMember, Entry, Log, Metric)


mkLog : String -> List Metric -> Log
mkLog id metrics =
    { id = id
    , name = id
    , metrics = metrics
    , description = ""
    , startDate = fromRataDie 1
    , collectionId = Just "c1"
    , createdAt = Time.millisToPosix 0
    , updatedAt = Time.millisToPosix 0
    }


mkEntry : String -> Int -> List Float -> Entry
mkEntry lid rd qs =
    { id = "e" ++ lid ++ String.fromInt rd
    , logId = lid
    , date = fromRataDie rd
    , values = List.map (\q -> { quantity = q, description = "" }) qs
    }


mkMember : Log -> List Entry -> CollectionMember
mkMember log entries =
    { log = log
    , entries = entries
    , streakStats = { current = 0, average = Nothing, longest = 0 }
    }


suite : Test
suite =
    describe "computeCombinedTotals"
        [ test "empty collection: no totals" <|
            \_ ->
                Collection.computeCombinedTotals (fromRataDie 1) []
                    |> Expect.equal []
        , test "single metric in collection: no combined total (contributors < 2)" <|
            \_ ->
                let
                    l =
                        mkLog "a" [ { name = "m", unit = "min" } ]

                    es =
                        [ mkEntry "a" 1 [ 10 ] ]
                in
                Collection.computeCombinedTotals (fromRataDie 1) [ mkMember l es ]
                    |> Expect.equal []
        , test "two single-metric logs sharing a unit: one combined total" <|
            \_ ->
                let
                    la =
                        mkLog "a" [ { name = "m1", unit = "min" } ]

                    lb =
                        mkLog "b" [ { name = "m2", unit = "min" } ]

                    ea =
                        [ mkEntry "a" 1 [ 10 ], mkEntry "a" 2 [ 5 ] ]

                    eb =
                        [ mkEntry "b" 1 [ 15 ] ]
                in
                case Collection.computeCombinedTotals (fromRataDie 1) [ mkMember la ea, mkMember lb eb ] of
                    [ t ] ->
                        Expect.all
                            [ \x -> Expect.equal "min" x.unit
                            , \x -> Expect.within (Expect.Absolute 0.001) 30 x.total
                            , \x -> Expect.equal (Just 15) x.average
                            , \x -> Expect.equal 2 x.days
                            , \x -> Expect.equal 2 x.contributors
                            ]
                            t

                    other ->
                        Expect.fail ("expected one total, got " ++ String.fromInt (List.length other))
        , test "different units: one total per unit that has >= 2 contributors" <|
            \_ ->
                let
                    la =
                        mkLog "a" [ { name = "d", unit = "km" } ]

                    lb =
                        mkLog "b" [ { name = "d", unit = "km" } ]

                    lc =
                        mkLog "c" [ { name = "m", unit = "min" } ]

                    ea =
                        [ mkEntry "a" 1 [ 3 ] ]

                    eb =
                        [ mkEntry "b" 1 [ 4 ] ]

                    ec =
                        [ mkEntry "c" 1 [ 30 ] ]
                in
                Collection.computeCombinedTotals (fromRataDie 1)
                    [ mkMember la ea, mkMember lb eb, mkMember lc ec ]
                    |> List.map .unit
                    |> Expect.equal [ "km" ]
        , test "multi-metric log feeds multiple unit totals" <|
            \_ ->
                let
                    la =
                        mkLog "a" [ { name = "d", unit = "km" }, { name = "t", unit = "min" } ]

                    lb =
                        mkLog "b" [ { name = "d", unit = "km" } ]

                    lc =
                        mkLog "c" [ { name = "t", unit = "min" } ]

                    ea =
                        [ mkEntry "a" 1 [ 3, 30 ] ]

                    eb =
                        [ mkEntry "b" 1 [ 4 ] ]

                    ec =
                        [ mkEntry "c" 1 [ 45 ] ]

                    totals =
                        Collection.computeCombinedTotals (fromRataDie 1)
                            [ mkMember la ea, mkMember lb eb, mkMember lc ec ]
                in
                Expect.equalLists [ "km", "min" ] (List.sort (List.map .unit totals))
        ]
