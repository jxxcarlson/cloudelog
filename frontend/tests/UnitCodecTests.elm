module UnitCodecTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types exposing (Unit(..), unitToString, unitFromString)


suite : Test
suite =
    describe "Unit codec"
        [ test "minutes round-trips" <|
            \_ -> unitFromString (unitToString Minutes) |> Expect.equal Minutes
        , test "hours round-trips" <|
            \_ -> unitFromString (unitToString Hours) |> Expect.equal Hours
        , test "kilometers round-trips" <|
            \_ -> unitFromString (unitToString Kilometers) |> Expect.equal Kilometers
        , test "miles round-trips" <|
            \_ -> unitFromString (unitToString Miles) |> Expect.equal Miles
        , test "custom round-trips" <|
            \_ -> unitFromString (unitToString (Custom "pages")) |> Expect.equal (Custom "pages")
        , test "unknown decodes to Custom" <|
            \_ -> unitFromString "widgets" |> Expect.equal (Custom "widgets")
        , test "case: MINUTES decodes to Minutes" <|
            \_ -> unitFromString "MINUTES" |> Expect.equal Minutes
        ]
