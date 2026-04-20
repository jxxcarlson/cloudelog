module StreakStatsDecoderTests exposing (suite)

import Api
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "streakStatsDecoder"
        [ test "decodes a populated streakStats object" <|
            \_ ->
                let
                    json =
                        """{ "current": 3, "average": 2.5, "longest": 7 }"""
                in
                case D.decodeString Api.streakStatsDecoder json of
                    Ok ss ->
                        Expect.all
                            [ \s -> Expect.equal 3 s.current
                            , \s -> Expect.equal (Just 2.5) s.average
                            , \s -> Expect.equal 7 s.longest
                            ]
                            ss

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "decodes null average as Nothing" <|
            \_ ->
                let
                    json =
                        """{ "current": 0, "average": null, "longest": 0 }"""
                in
                case D.decodeString Api.streakStatsDecoder json of
                    Ok ss ->
                        Expect.equal Nothing ss.average

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
