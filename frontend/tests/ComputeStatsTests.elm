module ComputeStatsTests exposing (suite)

import Date exposing (Date)
import Expect
import LogView exposing (Stats, computeStats)
import Test exposing (Test, describe, test)
import Types exposing (Entry)


-- helpers
d : Int -> Int -> Int -> Date
d y m day =
    Date.fromCalendarDate y (dateMonth m) day

dateMonth : Int -> Date.Month
dateMonth n =
    Date.numberToMonth n

e : String -> Date -> Float -> Entry
e eid dt q =
    { id = eid, logId = "L1", date = dt, quantity = q, description = "" }


suite : Test
suite =
    describe "LogView.computeStats"
        [ test "empty list: all zero / Nothing" <|
            \_ ->
                computeStats [] (d 2026 4 18)
                    |> Expect.equal { days = 0, skipped = 0, total = 0, average = Nothing }
        , test "single entry on today: days=1, total=q, average=Just q" <|
            \_ ->
                computeStats [ e "1" (d 2026 4 18) 30 ] (d 2026 4 18)
                    |> Expect.equal { days = 1, skipped = 0, total = 30, average = Just 30 }
        , test "one entry three days ago: days=4, active=1, avg=total/1" <|
            \_ ->
                computeStats [ e "1" (d 2026 4 15) 30 ] (d 2026 4 18)
                    |> Expect.equal { days = 4, skipped = 0, total = 30, average = Just 30 }
        , test "with skips: two real, one skip, over 3 days" <|
            \_ ->
                computeStats
                    [ e "1" (d 2026 4 16) 20
                    , e "2" (d 2026 4 17) 0
                    , e "3" (d 2026 4 18) 40
                    ]
                    (d 2026 4 18)
                    |> Expect.equal { days = 3, skipped = 1, total = 60, average = Just 30 }
        , test "all skips: average is Nothing" <|
            \_ ->
                computeStats
                    [ e "1" (d 2026 4 17) 0
                    , e "2" (d 2026 4 18) 0
                    ]
                    (d 2026 4 18)
                    |> Expect.equal { days = 2, skipped = 2, total = 0, average = Nothing }
        ]
