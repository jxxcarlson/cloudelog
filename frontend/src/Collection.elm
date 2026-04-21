module Collection exposing (Model, Msg, OutMsg(..), init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Http
import Types exposing (Collection, CollectionDetail, CollectionMember, Log)


type alias Model =
    { collectionId : String
    , today : Date
    , detail : Maybe CollectionDetail
    , loading : Bool
    , error : Maybe String
    }


type Msg
    = DetailFetched (Result Http.Error CollectionDetail)
    | OpenLog String


type OutMsg
    = NoOp
    | NavigateToLog String


init : String -> Date -> ( Model, Cmd Msg )
init cid today =
    ( { collectionId = cid
      , today = today
      , detail = Nothing
      , loading = True
      , error = Nothing
      }
    , Api.getCollection cid DetailFetched
    )


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        DetailFetched (Ok d) ->
            ( { model | detail = Just d, loading = False, error = Nothing }
            , Cmd.none
            , NoOp
            )

        DetailFetched (Err err) ->
            ( { model | loading = False, error = Just (Api.apiErrorToString err) }
            , Cmd.none
            , NoOp
            )

        OpenLog id ->
            ( model, Cmd.none, NavigateToLog id )


view : Model -> Html Msg
view model =
    case ( model.loading, model.detail ) of
        ( True, _ ) ->
            p [] [ text "Loading..." ]

        ( _, Nothing ) ->
            case model.error of
                Just e ->
                    div [] [ text ("Error: " ++ e) ]

                Nothing ->
                    div [] [ text "No data" ]

        ( False, Just d ) ->
            div []
                [ h1 [] [ text d.collection.name ]
                , if String.isEmpty d.collection.description then
                    text ""

                  else
                    p [ style "color" "#555" ] [ text d.collection.description ]
                , h3 [] [ text "Members" ]
                , div []
                    (List.map viewMemberRow d.members)
                ]


viewMemberRow : CollectionMember -> Html Msg
viewMemberRow m =
    div
        [ class "row"
        , onClick (OpenLog m.log.id)
        , style "cursor" "pointer"
        ]
        [ div [ class "desc" ]
            [ strong [] [ text m.log.name ]
            , text
                (" — "
                    ++ (m.log.metrics
                            |> List.map .unit
                            |> String.join ", "
                       )
                )
            ]
        ]
