module Collection exposing (Model, Msg, OutMsg(..), init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Collection, CollectionDetail, CollectionMember, Log, Metric)


type alias ValueDraft =
    { qty : String, desc : String }


type alias LogDraft =
    { logId : String, values : List ValueDraft }


type alias Model =
    { collectionId : String
    , today : Date
    , detail : Maybe CollectionDetail
    , loading : Bool
    , error : Maybe String
    , drafts : List LogDraft
    , submitting : Bool
    }


type Msg
    = DetailFetched (Result Http.Error CollectionDetail)
    | OpenLog String
    | DraftQtyChanged String Int String
    | DraftDescChanged String Int String
    | SubmitCombined
    | CombinedPosted (Result Http.Error CollectionDetail)


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
      , drafts = []
      , submitting = False
      }
    , Api.getCollection cid DetailFetched
    )


emptyDraftsFor : List CollectionMember -> List LogDraft
emptyDraftsFor members =
    List.map
        (\m ->
            { logId = m.log.id
            , values = List.map (\_ -> { qty = "", desc = "" }) m.log.metrics
            }
        )
        members


{-| Local copy of `updateAt` — intentionally duplicated to avoid a
cross-module import from `LogView.elm` / `LogList.elm`.
-}
updateAt : Int -> (a -> a) -> List a -> List a
updateAt i f xs =
    List.indexedMap
        (\j x ->
            if i == j then
                f x

            else
                x
        )
        xs


combineMaybe : List (Maybe a) -> Maybe (List a)
combineMaybe =
    List.foldr (\mx macc -> Maybe.map2 (::) mx macc) (Just [])


updateDraftValues : String -> (List ValueDraft -> List ValueDraft) -> List LogDraft -> List LogDraft
updateDraftValues logId f drafts =
    List.map
        (\ld ->
            if ld.logId == logId then
                { ld | values = f ld.values }

            else
                ld
        )
        drafts


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        DetailFetched (Ok d) ->
            ( { model
                | detail = Just d
                , loading = False
                , error = Nothing
                , drafts = emptyDraftsFor d.members
              }
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

        DraftQtyChanged logId i s ->
            ( { model
                | drafts =
                    updateDraftValues logId
                        (updateAt i (\v -> { v | qty = s }))
                        model.drafts
              }
            , Cmd.none
            , NoOp
            )

        DraftDescChanged logId i s ->
            ( { model
                | drafts =
                    updateDraftValues logId
                        (updateAt i (\v -> { v | desc = s }))
                        model.drafts
              }
            , Cmd.none
            , NoOp
            )

        SubmitCombined ->
            let
                parseValue v =
                    case String.toFloat (String.trim v.qty) of
                        Just q ->
                            Just { quantity = q, description = v.desc }

                        Nothing ->
                            if String.isEmpty (String.trim v.qty) && String.isEmpty v.desc then
                                Just { quantity = 0, description = "" }

                            else
                                Nothing

                parsePerLog ld =
                    case combineMaybe (List.map parseValue ld.values) of
                        Just vs ->
                            Just { logId = ld.logId, values = vs }

                        Nothing ->
                            Nothing

                parsed =
                    List.map parsePerLog model.drafts
            in
            if List.any ((==) Nothing) parsed then
                ( { model | error = Just "every quantity must be a number (leave a row fully blank to skip)." }
                , Cmd.none
                , NoOp
                )

            else
                let
                    logEntries =
                        List.filterMap identity parsed
                in
                ( { model | submitting = True, error = Nothing }
                , Api.postCombinedEntry model.collectionId
                    { entryDate = model.today, logEntries = logEntries }
                    CombinedPosted
                , NoOp
                )

        CombinedPosted (Ok d) ->
            ( { model
                | detail = Just d
                , drafts = emptyDraftsFor d.members
                , submitting = False
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )

        CombinedPosted (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }
            , Cmd.none
            , NoOp
            )


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
                , viewCombinedForm d.members model.drafts model.submitting
                , case model.error of
                    Just e ->
                        div [ class "flash" ] [ text e ]

                    Nothing ->
                        text ""
                , h3 [] [ text "Members" ]
                , div []
                    (List.map viewMemberRow d.members)
                ]


viewCombinedForm : List CollectionMember -> List LogDraft -> Bool -> Html Msg
viewCombinedForm members drafts submitting =
    Html.form
        [ onSubmit SubmitCombined
        , style "display" "block"
        , style "margin" "1rem 0"
        ]
        (h3 [] [ text "Today's practice" ]
            :: List.map2 viewLogDraftBlock members drafts
            ++ [ button
                    [ type_ "submit"
                    , class "primary"
                    , disabled submitting
                    , style "margin-top" "0.5rem"
                    ]
                    [ text
                        (if submitting then
                            "Recording…"

                         else
                            "Record today"
                        )
                    ]
               ]
        )


viewLogDraftBlock : CollectionMember -> LogDraft -> Html Msg
viewLogDraftBlock m ld =
    div [ style "margin-bottom" "0.5rem" ]
        (List.indexedMap (viewValueDraftRow m.log.name m.log.metrics ld.logId) ld.values)


viewValueDraftRow : String -> List Metric -> String -> Int -> ValueDraft -> Html Msg
viewValueDraftRow logName metrics logId i v =
    let
        metric =
            metrics |> List.drop i |> List.head

        labelText =
            case metric of
                Just mm ->
                    logName
                        ++ " — "
                        ++ mm.name
                        ++ (if String.isEmpty mm.unit then
                                ""

                            else
                                " (" ++ mm.unit ++ ")"
                           )

                Nothing ->
                    logName
    in
    div
        [ style "display" "flex"
        , style "gap" "0.5rem"
        , style "align-items" "center"
        , style "margin-bottom" "0.25rem"
        ]
        [ div [ style "flex" "0 0 auto", style "min-width" "14rem", style "color" "#555" ]
            [ text labelText ]
        , input
            [ type_ "number"
            , step "any"
            , placeholder "quantity"
            , value v.qty
            , onInput (DraftQtyChanged logId i)
            , style "width" "7rem"
            , style "flex" "0 0 auto"
            ]
            []
        , input
            [ type_ "text"
            , placeholder "note (optional)"
            , value v.desc
            , onInput (DraftDescChanged logId i)
            , style "flex" "1 1 auto"
            , style "min-width" "0"
            ]
            []
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
