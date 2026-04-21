module CollectionDecoderTests exposing (suite)

import Api
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "collection decoders"
        [ test "collectionSummaryDecoder parses memberCount" <|
            \_ ->
                let
                    json =
                        """
                        { "id": "c1"
                        , "name": "Piano"
                        , "description": "daily"
                        , "memberCount": 4
                        , "createdAt": "2026-04-21T00:00:00Z"
                        , "updatedAt": "2026-04-21T00:00:00Z"
                        }
                        """
                in
                case D.decodeString Api.collectionSummaryDecoder json of
                    Ok s ->
                        Expect.equal 4 s.memberCount

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "collectionDetailDecoder parses an empty members list" <|
            \_ ->
                let
                    json =
                        """
                        { "collection":
                            { "id": "c1", "name": "C", "description": ""
                            , "createdAt": "2026-04-21T00:00:00Z"
                            , "updatedAt": "2026-04-21T00:00:00Z" }
                        , "members": []
                        }
                        """
                in
                case D.decodeString Api.collectionDetailDecoder json of
                    Ok d ->
                        Expect.equal 0 (List.length d.members)

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
