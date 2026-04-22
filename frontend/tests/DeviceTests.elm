module DeviceTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types exposing (Device(..), classify)


suite : Test
suite =
    describe "Types.classify"
        [ test "just below breakpoint is Phone" <|
            \_ -> Expect.equal Phone (classify 599)
        , test "at breakpoint is Desktop" <|
            \_ -> Expect.equal Desktop (classify 600)
        , test "very small width is Phone" <|
            \_ -> Expect.equal Phone (classify 0)
        , test "typical desktop width is Desktop" <|
            \_ -> Expect.equal Desktop (classify 1920)
        ]
