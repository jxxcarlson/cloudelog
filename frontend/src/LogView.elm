module LogView exposing (Model, Msg(..), OutMsg(..), Stats, computeStats, init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Entry, Log, StreakStats, Unit(..), unitToString)



---------------------------------------------------------------
-- Stats (previously defined; kept for test compatibility)
---------------------------------------------------------------


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



---------------------------------------------------------------
-- page Model / Msg
---------------------------------------------------------------


type alias EditDraft =
    { entryId : String
    , qty : String
    , desc : String
    , submitting : Bool
    }


type alias DescDraft =
    { text : String
    , submitting : Bool
    }


type alias Model =
    { logId : String
    , today : Date
    , log : Maybe Log
    , entries : List Entry
    , streakStats : Maybe StreakStats
    , loading : Bool
    , error : Maybe String
    , newQty : String
    , newDesc : String
    , submitting : Bool
    , editing : Maybe EditDraft
    , editingDesc : Maybe DescDraft
    }


init : String -> Date -> ( Model, Cmd Msg )
init logId today =
    ( { logId = logId
      , today = today
      , log = Nothing
      , entries = []
      , streakStats = Nothing
      , loading = True
      , error = Nothing
      , newQty = ""
      , newDesc = ""
      , submitting = False
      , editing = Nothing
      , editingDesc = Nothing
      }
    , Api.getLog logId LogFetched
    )


type Msg
    = LogFetched (Result Http.Error { log : Log, entries : List Entry, streakStats : StreakStats })
    | QtyChanged String
    | DescChanged String
    | AddEntry
    | EntryPosted (Result Http.Error (List Entry))
    | DeleteEntry String
    | EntryDeleted String (Result Http.Error ())
    | StartEdit Entry
    | EditQtyChanged String
    | EditDescChanged String
    | SaveEdit
    | CancelEdit
    | EditSaved (Result Http.Error Entry)
    | StartEditDesc
    | DescDraftChanged String
    | SaveDesc
    | CancelDesc
    | DescSaved (Result Http.Error Log)


type OutMsg
    = NoOp


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        LogFetched (Ok { log, entries, streakStats }) ->
            ( { model
                | log = Just log
                , entries = entries
                , streakStats = Just streakStats
                , loading = False
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )

        LogFetched (Err err) ->
            ( { model | loading = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        QtyChanged s ->
            ( { model | newQty = s }, Cmd.none, NoOp )

        DescChanged s ->
            ( { model | newDesc = s }, Cmd.none, NoOp )

        AddEntry ->
            case String.toFloat (String.trim model.newQty) of
                Just q ->
                    ( { model | submitting = True, error = Nothing }
                    , Api.postEntry model.logId
                        { entryDate = model.today, quantity = q, description = model.newDesc }
                        EntryPosted
                    , NoOp
                    )

                Nothing ->
                    ( { model | error = Just "Quantity must be a number." }, Cmd.none, NoOp )

        EntryPosted (Ok entries) ->
            ( { model
                | entries = entries
                , newQty = ""
                , newDesc = ""
                , submitting = False
                , error = Nothing
              }
            , Api.getLog model.logId LogFetched
            , NoOp
            )

        EntryPosted (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        DeleteEntry eid ->
            ( model, Api.deleteEntry eid (EntryDeleted eid), NoOp )

        EntryDeleted eid (Ok ()) ->
            ( { model | entries = List.filter (\e -> e.id /= eid) model.entries }
            , Api.getLog model.logId LogFetched
            , NoOp
            )

        EntryDeleted _ (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        StartEdit e ->
            ( { model
                | editing =
                    Just
                        { entryId = e.id
                        , qty = String.fromFloat e.quantity
                        , desc = e.description
                        , submitting = False
                        }
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )

        EditQtyChanged s ->
            case model.editing of
                Just d ->
                    ( { model | editing = Just { d | qty = s } }, Cmd.none, NoOp )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        EditDescChanged s ->
            case model.editing of
                Just d ->
                    ( { model | editing = Just { d | desc = s } }, Cmd.none, NoOp )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        CancelEdit ->
            ( { model | editing = Nothing }, Cmd.none, NoOp )

        SaveEdit ->
            case model.editing of
                Just d ->
                    case String.toFloat (String.trim d.qty) of
                        Just q ->
                            ( { model | editing = Just { d | submitting = True }, error = Nothing }
                            , Api.updateEntry d.entryId { quantity = q, description = d.desc } EditSaved
                            , NoOp
                            )

                        Nothing ->
                            ( { model | error = Just "Quantity must be a number." }, Cmd.none, NoOp )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        EditSaved (Ok updated) ->
            let
                replace e =
                    if e.id == updated.id then
                        updated

                    else
                        e
            in
            ( { model | entries = List.map replace model.entries, editing = Nothing, error = Nothing }
            , Api.getLog model.logId LogFetched
            , NoOp
            )

        EditSaved (Err err) ->
            ( { model
                | editing =
                    Maybe.map (\d -> { d | submitting = False }) model.editing
                , error = Just (Api.apiErrorToString err)
              }
            , Cmd.none
            , NoOp
            )

        StartEditDesc ->
            case model.log of
                Just log ->
                    ( { model
                        | editingDesc = Just { text = log.description, submitting = False }
                        , error = Nothing
                      }
                    , Cmd.none
                    , NoOp
                    )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        DescDraftChanged s ->
            case model.editingDesc of
                Just d ->
                    ( { model | editingDesc = Just { d | text = s } }, Cmd.none, NoOp )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        SaveDesc ->
            case ( model.log, model.editingDesc ) of
                ( Just log, Just d ) ->
                    ( { model | editingDesc = Just { d | submitting = True }, error = Nothing }
                    , Api.updateLog log.id
                        { name = log.name, description = d.text, unit = Nothing }
                        DescSaved
                    , NoOp
                    )

                _ ->
                    ( model, Cmd.none, NoOp )

        CancelDesc ->
            ( { model | editingDesc = Nothing }, Cmd.none, NoOp )

        DescSaved (Ok log) ->
            ( { model | log = Just log, editingDesc = Nothing, error = Nothing }
            , Cmd.none
            , NoOp
            )

        DescSaved (Err err) ->
            ( { model
                | editingDesc =
                    Maybe.map (\d -> { d | submitting = False }) model.editingDesc
                , error = Just (Api.apiErrorToString err)
              }
            , Cmd.none
            , NoOp
            )


view : Model -> Html Msg
view model =
    case model.log of
        Nothing ->
            if model.loading then
                p [] [ text "Loading log…" ]

            else
                p []
                    [ text (Maybe.withDefault "Log not available." model.error) ]

        Just log ->
            let
                stats =
                    computeStats model.entries model.today
            in
            div []
                [ h1 [] [ text log.name ]
                , p []
                    [ text ("Unit: " ++ unitToString log.unit)
                    , text (" · since " ++ Date.toIsoString log.startDate)
                    ]
                , viewStats stats
                , viewStreakStats model.streakStats
                , viewDescription model.editingDesc log
                , hr
                    [ style "margin" "0.5rem 0 1rem 0"
                    , style "border" "none"
                    , style "border-top" "1px solid #ddd"
                    ]
                    []
                , viewAddForm model
                , case model.error of
                    Just e ->
                        div [ class "flash" ] [ text e ]

                    Nothing ->
                        text ""
                , div []
                    (List.map
                        (viewEntryRow model.editing)
                        (List.reverse (List.sortBy (Date.toRataDie << .date) model.entries))
                    )
                ]


viewDescription : Maybe DescDraft -> Log -> Html Msg
viewDescription editing log =
    case editing of
        Just d ->
            let
                smallBtn =
                    [ style "padding" "0.2rem 0.5rem"
                    , style "font-size" "0.85rem"
                    ]
            in
            div
                [ style "margin" "0.5rem 0"
                , style "display" "flex"
                , style "gap" "0.5rem"
                , style "align-items" "stretch"
                ]
                [ textarea
                    [ rows 3
                    , value d.text
                    , onInput DescDraftChanged
                    , placeholder "description"
                    , style "flex" "1 1 auto"
                    , style "min-width" "0"
                    , style "box-sizing" "border-box"
                    , style "font-family" "inherit"
                    , style "font-size" "1rem"
                    ]
                    []
                , div
                    [ style "display" "flex"
                    , style "flex-direction" "column"
                    , style "justify-content" "space-between"
                    , style "flex" "0 0 auto"
                    ]
                    [ button (onClick SaveDesc :: disabled d.submitting :: smallBtn)
                        [ text
                            (if d.submitting then
                                "Saving…"

                             else
                                "Save"
                            )
                        ]
                    , button (onClick CancelDesc :: disabled d.submitting :: smallBtn) [ text "Cancel" ]
                    ]
                ]

        Nothing ->
            let
                smallBtn =
                    [ style "padding" "0.2rem 0.5rem"
                    , style "font-size" "0.85rem"
                    , style "flex" "0 0 auto"
                    ]
            in
            div
                [ style "margin" "0.5rem 0"
                , style "display" "flex"
                , style "gap" "0.5rem"
                , style "align-items" "flex-start"
                ]
                [ p
                    [ style "color" "#555"
                    , style "margin" "0"
                    , style "flex" "1 1 auto"
                    ]
                    [ text log.description ]
                , button (onClick StartEditDesc :: smallBtn) [ text "Edit" ]
                ]


viewStats : Stats -> Html msg
viewStats s =
    let
        fmt : Float -> String
        fmt n =
            String.fromFloat n

        -- One decimal place, padded with ".0" when rounding yields an integer.
        fmt1 : Float -> String
        fmt1 n =
            let
                rounded =
                    toFloat (round (n * 10)) / 10

                base =
                    String.fromFloat rounded
            in
            if String.contains "." base then
                base

            else
                base ++ ".0"

        maybeFmt1 : Maybe Float -> String
        maybeFmt1 =
            Maybe.map fmt1 >> Maybe.withDefault "—"
    in
    div [ class "stats" ]
        [ div [] [ text ("Days: " ++ String.fromInt s.days) ]
        , div [] [ text ("Skipped: " ++ String.fromInt s.skipped) ]
        , div [] [ text ("Total: " ++ fmt s.total) ]
        , div [] [ text ("Avg: " ++ maybeFmt1 s.average) ]
        ]


viewStreakStats : Maybe StreakStats -> Html msg
viewStreakStats mss =
    let
        dash =
            "—"

        intCell label n =
            div []
                [ text
                    (label
                        ++ ": "
                        ++ (if n <= 0 then
                                dash

                            else
                                String.fromInt n
                           )
                    )
                ]

        avgCell label ma =
            div []
                [ text
                    (label
                        ++ ": "
                        ++ (case ma of
                                Just a ->
                                    -- one decimal place, matches Avg in viewStats
                                    let
                                        rounded =
                                            toFloat (round (a * 10)) / 10
                                    in
                                    String.fromFloat rounded

                                Nothing ->
                                    dash
                           )
                    )
                ]
    in
    case mss of
        Nothing ->
            text ""

        Just ss ->
            div [ class "stats" ]
                [ intCell "Current streak" ss.current
                , avgCell "Avg streak" ss.average
                , intCell "Longest streak" ss.longest
                ]


viewAddForm : Model -> Html Msg
viewAddForm m =
    Html.form [ onSubmit AddEntry, style "width" "100%" ]
        [ input
            [ type_ "number"
            , step "any"
            , placeholder "quantity"
            , value m.newQty
            , onInput QtyChanged
            , style "width" "7rem"
            , style "flex" "0 0 auto"
            ]
            []
        , input
            [ placeholder "note (optional)"
            , value m.newDesc
            , onInput DescChanged
            , style "flex" "1 1 auto"
            , style "min-width" "0"
            ]
            []
        , button [ type_ "submit", class "primary", disabled m.submitting, style "flex" "0 0 auto" ]
            [ text
                (if m.submitting then
                    "Adding…"

                 else
                    "Add"
                )
            ]
        ]


viewEntryRow : Maybe EditDraft -> Entry -> Html Msg
viewEntryRow editing e =
    case editing of
        Just d ->
            if d.entryId == e.id then
                viewEditRow e d

            else
                viewReadRow e

        Nothing ->
            viewReadRow e


viewReadRow : Entry -> Html Msg
viewReadRow e =
    div [ class "row" ]
        [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
        , div [ class "qty" ] [ text (String.fromFloat e.quantity) ]
        , div [ class "desc" ]
            [ text
                (if e.quantity == 0 && String.isEmpty e.description then
                    "(skipped)"

                 else
                    e.description
                )
            ]
        , div [ class "ctrls" ]
            [ button [ onClick (StartEdit e) ] [ text "Edit" ]
            , button [ onClick (DeleteEntry e.id) ] [ text "Del" ]
            ]
        ]


viewEditRow : Entry -> EditDraft -> Html Msg
viewEditRow e d =
    div [ class "row" ]
        [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
        , div [ class "qty" ]
            [ input
                [ type_ "number"
                , step "any"
                , value d.qty
                , onInput EditQtyChanged
                ]
                []
            ]
        , div [ class "desc" ]
            [ input
                [ value d.desc
                , onInput EditDescChanged
                , placeholder "note (optional)"
                ]
                []
            ]
        , div [ class "ctrls" ]
            [ button [ onClick SaveEdit, disabled d.submitting ]
                [ text
                    (if d.submitting then
                        "Saving…"

                     else
                        "Save"
                    )
                ]
            , button [ onClick CancelEdit, disabled d.submitting ] [ text "Cancel" ]
            ]
        ]
