module LogView exposing (MetricStats, Model, Msg(..), OutMsg(..), Stats, ValueDraft, computeStats, init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (CollectionSummary, Entry, EntryValue, Log, Metric, StreakStats)



---------------------------------------------------------------
-- Stats (previously defined; kept for test compatibility)
---------------------------------------------------------------


type alias Stats =
    { days : Int
    , skipped : Int
    , perMetric : List MetricStats
    }


type alias MetricStats =
    { name : String
    , unit : String
    , total : Float
    , average : Maybe Float
    }


computeStats : Maybe Log -> List Entry -> Date -> Stats
computeStats mLog entries today =
    let
        metrics =
            case mLog of
                Just l ->
                    l.metrics

                Nothing ->
                    []

        sorted =
            List.sortBy (Date.toRataDie << .date) entries

        days =
            case sorted of
                [] ->
                    0

                first :: _ ->
                    Date.diff Date.Days first.date today + 1

        isSkipped e =
            List.all (\v -> v.quantity == 0) e.values

        skipped =
            List.length (List.filter isSkipped entries)

        perMetric =
            List.indexedMap
                (\i m ->
                    let
                        qtys =
                            List.filterMap
                                (\e ->
                                    e.values
                                        |> List.drop i
                                        |> List.head
                                        |> Maybe.map .quantity
                                )
                                entries

                        total =
                            List.sum qtys

                        active =
                            List.length (List.filter (\q -> q /= 0) qtys)

                        average =
                            if active > 0 then
                                Just (total / toFloat active)

                            else
                                Nothing
                    in
                    { name = m.name, unit = m.unit, total = total, average = average }
                )
                metrics
    in
    { days = days, skipped = skipped, perMetric = perMetric }



---------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------


{-| Local copy of `updateAt` — intentionally duplicated from `LogList.elm`
to avoid a cross-module import between view modules.
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


abbrevUnit : String -> String
abbrevUnit unit =
    case unit of
        "minutes" ->
            "min"

        _ ->
            unit


type alias ValueDraft =
    { qty : String
    , desc : String
    }


emptyValueDrafts : List Metric -> List ValueDraft
emptyValueDrafts metrics =
    List.map (\_ -> { qty = "", desc = "" }) metrics



---------------------------------------------------------------
-- page Model / Msg
---------------------------------------------------------------


type alias EditDraft =
    { entryId : String
    , values : List ValueDraft
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
    , newValues : List ValueDraft
    , submitting : Bool
    , editing : Maybe EditDraft
    , editingDesc : Maybe DescDraft
    , availableCollections : List CollectionSummary
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
      , newValues = []
      , submitting = False
      , editing = Nothing
      , editingDesc = Nothing
      , availableCollections = []
      }
    , Cmd.batch
        [ Api.getLog logId LogFetched
        , Api.listCollections CollectionsFetched
        ]
    )


type Msg
    = LogFetched (Result Http.Error { log : Log, entries : List Entry, streakStats : StreakStats })
    | NewQtyChanged Int String
    | NewDescChanged Int String
    | AddEntry
    | EntryPosted (Result Http.Error (List Entry))
    | DeleteEntry String
    | EntryDeleted String (Result Http.Error ())
    | StartEdit Entry
    | EditQtyChanged Int String
    | EditDescChanged Int String
    | SaveEdit
    | CancelEdit
    | EditSaved (Result Http.Error Entry)
    | StartEditDesc
    | DescDraftChanged String
    | SaveDesc
    | CancelDesc
    | DescSaved (Result Http.Error Log)
    | CollectionsFetched (Result Http.Error (List CollectionSummary))
    | CollectionSelected String
    | CollectionSet (Result Http.Error Log)


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
                , newValues = emptyValueDrafts log.metrics
                , loading = False
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )

        LogFetched (Err err) ->
            ( { model | loading = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        NewQtyChanged i s ->
            ( { model | newValues = updateAt i (\v -> { v | qty = s }) model.newValues }
            , Cmd.none
            , NoOp
            )

        NewDescChanged i s ->
            ( { model | newValues = updateAt i (\v -> { v | desc = s }) model.newValues }
            , Cmd.none
            , NoOp
            )

        AddEntry ->
            let
                parseValue v =
                    case String.toFloat (String.trim v.qty) of
                        Just q ->
                            Just { quantity = q, description = v.desc }

                        Nothing ->
                            Nothing

                parsed =
                    List.map parseValue model.newValues
            in
            if List.any ((==) Nothing) parsed then
                ( { model | error = Just "every quantity must be a number." }, Cmd.none, NoOp )

            else
                let
                    values =
                        List.filterMap identity parsed
                in
                ( { model | submitting = True, error = Nothing }
                , Api.postEntry model.logId
                    { entryDate = model.today, values = values }
                    EntryPosted
                , NoOp
                )

        EntryPosted (Ok entries) ->
            ( { model
                | entries = entries
                , newValues =
                    case model.log of
                        Just l ->
                            emptyValueDrafts l.metrics

                        Nothing ->
                            []
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
                        , values =
                            List.map
                                (\v -> { qty = String.fromFloat v.quantity, desc = v.description })
                                e.values
                        , submitting = False
                        }
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )

        EditQtyChanged i s ->
            case model.editing of
                Just d ->
                    ( { model | editing = Just { d | values = updateAt i (\v -> { v | qty = s }) d.values } }
                    , Cmd.none
                    , NoOp
                    )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        EditDescChanged i s ->
            case model.editing of
                Just d ->
                    ( { model | editing = Just { d | values = updateAt i (\v -> { v | desc = s }) d.values } }
                    , Cmd.none
                    , NoOp
                    )

                Nothing ->
                    ( model, Cmd.none, NoOp )

        CancelEdit ->
            ( { model | editing = Nothing }, Cmd.none, NoOp )

        SaveEdit ->
            case model.editing of
                Just d ->
                    let
                        parseValue v =
                            case String.toFloat (String.trim v.qty) of
                                Just q ->
                                    Just { quantity = q, description = v.desc }

                                Nothing ->
                                    Nothing

                        parsed =
                            List.map parseValue d.values
                    in
                    if List.any ((==) Nothing) parsed then
                        ( { model | error = Just "every quantity must be a number." }, Cmd.none, NoOp )

                    else
                        let
                            values =
                                List.filterMap identity parsed
                        in
                        ( { model | editing = Just { d | submitting = True }, error = Nothing }
                        , Api.updateEntry d.entryId { values = values } EditSaved
                        , NoOp
                        )

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
                        { name = log.name, description = d.text, metrics = Nothing }
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

        CollectionsFetched (Ok cs) ->
            ( { model | availableCollections = cs }, Cmd.none, NoOp )

        CollectionsFetched (Err _) ->
            ( model, Cmd.none, NoOp )

        CollectionSelected "" ->
            ( model, Api.setLogCollection model.logId Nothing CollectionSet, NoOp )

        CollectionSelected cid ->
            ( model, Api.setLogCollection model.logId (Just cid) CollectionSet, NoOp )

        CollectionSet (Ok log) ->
            ( { model | log = Just log, error = Nothing }, Cmd.none, NoOp )

        CollectionSet (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )


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
                    computeStats model.log model.entries model.today
            in
            div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.5rem"
                , style "align-items" "stretch"
                ]
                [ div
                    [ style "display" "flex"
                    , style "align-items" "baseline"
                    , style "gap" "1.5rem"
                    , style "flex-wrap" "wrap"
                    ]
                    (h1
                        [ style "margin" "0"
                        , style "line-height" "1"
                        ]
                        [ text log.name ]
                        :: viewStatsCells stats
                    )
                , viewStatsTable stats
                , viewStreakRow model.streakStats log.startDate log model.availableCollections
                , hr
                    [ style "margin" "0"
                    , style "border" "none"
                    , style "border-top" "1px solid #ddd"
                    ]
                    []
                , div []
                    [ viewDescription model.editingDesc log
                    , hr
                        [ style "margin" "0"
                        , style "border" "none"
                        , style "border-top" "1px solid #ddd"
                        ]
                        []
                    ]
                , viewNewEntryForm log.metrics model.newValues model.submitting
                , case model.error of
                    Just e ->
                        div [ class "flash" ] [ text e ]

                    Nothing ->
                        text ""
                , div []
                    (List.map
                        (viewEntryRow log.metrics model.editing)
                        (List.reverse (List.sortBy (Date.toRataDie << .date) model.entries))
                    )
                ]


viewStreakRow : Maybe StreakStats -> Date -> Log -> List CollectionSummary -> Html Msg
viewStreakRow mss startDate log availableCollections =
    let
        dash =
            "—"

        intStr n =
            if n <= 0 then
                dash

            else
                String.fromInt n

        avgStr ma =
            case ma of
                Just a ->
                    String.fromFloat (toFloat (round (a * 10)) / 10)

                Nothing ->
                    dash

        sinceCell =
            div pillStyle [ text ("Since " ++ Date.format "MMMM d, y" startDate) ]

        streaksCell ss =
            div pillStyle
                [ text
                    ("Streaks — current: "
                        ++ intStr ss.current
                        ++ " · avg: "
                        ++ avgStr ss.average
                        ++ " · longest: "
                        ++ intStr ss.longest
                    )
                ]

        collectionCell =
            div
                (pillStyle
                    ++ [ style "display" "flex"
                       , style "gap" "0.5rem"
                       , style "align-items" "baseline"
                       ]
                )
                [ span [ style "color" "#555" ] [ text "Collection:" ]
                , select
                    [ onInput CollectionSelected
                    , value (Maybe.withDefault "" log.collectionId)
                    ]
                    (option [ value "" ] [ text "— none —" ]
                        :: List.map
                            (\c ->
                                option
                                    [ value c.id
                                    , selected (log.collectionId == Just c.id)
                                    ]
                                    [ text c.name ]
                            )
                            availableCollections
                    )
                ]

        leftCells =
            case mss of
                Nothing ->
                    []

                Just ss ->
                    [ streaksCell ss ]

        rightGroup =
            div
                [ style "display" "flex"
                , style "gap" "1.5rem"
                , style "align-items" "baseline"
                , style "margin-left" "auto"
                , style "flex-wrap" "wrap"
                ]
                [ sinceCell, collectionCell ]
    in
    div
        [ style "display" "flex"
        , style "gap" "1.5rem"
        , style "align-items" "baseline"
        , style "flex-wrap" "wrap"
        , style "margin" "0"
        ]
        (leftCells ++ [ rightGroup ])


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
                [ style "margin" "0"
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
                [ style "margin" "0"
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


pillStyle : List (Html.Attribute msg)
pillStyle =
    [ style "background" "#f5f5f5"
    , style "padding" "0.3rem 0.6rem"
    , style "border-radius" "4px"
    , style "font-size" "0.95rem"
    ]


fmt : Float -> String
fmt =
    String.fromFloat


fmt1 : Float -> String
fmt1 a =
    String.fromFloat (toFloat (round (a * 10)) / 10)


viewStatsCells : Stats -> List (Html msg)
viewStatsCells s =
    let
        daysCell =
            div pillStyle [ text ("Days: " ++ String.fromInt s.days) ]

        skippedCell =
            div pillStyle [ text ("Skipped: " ++ String.fromInt s.skipped) ]

        avgText ms =
            case ms.average of
                Just a ->
                    fmt1 a ++ " " ++ abbrevUnit ms.unit

                Nothing ->
                    "—"
    in
    case s.perMetric of
        [ ms ] ->
            [ daysCell
            , skippedCell
            , div pillStyle [ text ("Total: " ++ fmt ms.total ++ " " ++ abbrevUnit ms.unit) ]
            , div pillStyle [ text ("Average: " ++ avgText ms) ]
            ]

        _ ->
            -- Multi-metric: Days/Skipped as pills; table renders separately in viewStatsTable.
            [ daysCell, skippedCell ]


viewStatsTable : Stats -> Html msg
viewStatsTable s =
    case s.perMetric of
        [] ->
            text ""

        [ _ ] ->
            -- Single-metric stats are already in the pill row above.
            text ""

        _ ->
            table
                [ style "border-collapse" "collapse"
                , style "margin" "0"
                , style "font-size" "0.95rem"
                ]
                [ thead []
                    [ tr []
                        [ metricTh "item"
                        , metricTh "total"
                        , metricTh "avg"
                        ]
                    ]
                , tbody [] (List.map viewMetricStatsRow s.perMetric)
                ]


metricTh : String -> Html msg
metricTh label =
    th
        [ style "text-align" "left"
        , style "padding" "0.2rem 0.75rem"
        , style "border-bottom" "1px solid #ccc"
        , style "font-weight" "normal"
        , style "color" "#555"
        ]
        [ text label ]


metricTd : String -> Html msg
metricTd content =
    td
        [ style "padding" "0.2rem 0.75rem"
        , style "border-bottom" "1px solid #eee"
        ]
        [ text content ]


viewMetricStatsRow : MetricStats -> Html msg
viewMetricStatsRow ms =
    let
        totalText =
            String.fromFloat ms.total ++ " " ++ abbrevUnit ms.unit

        avgText =
            case ms.average of
                Just a ->
                    String.fromFloat (toFloat (round (a * 10)) / 10) ++ " " ++ abbrevUnit ms.unit

                Nothing ->
                    "—"
    in
    tr []
        [ metricTd ms.name
        , metricTd totalText
        , metricTd avgText
        ]


viewNewEntryForm : List Metric -> List ValueDraft -> Bool -> Html Msg
viewNewEntryForm metrics drafts submitting =
    Html.form
        [ onSubmit AddEntry
        , style "width" "100%"
        , style "display" "block"
        ]
        (List.indexedMap (viewValueDraftRow metrics) drafts
            ++ [ button
                    [ type_ "submit"
                    , class "primary"
                    , disabled submitting
                    , style "flex" "0 0 auto"
                    , style "margin-top" "0.25rem"
                    ]
                    [ text
                        (if submitting then
                            "Adding…"

                         else
                            "Add entry"
                        )
                    ]
               ]
        )


viewValueDraftRow : List Metric -> Int -> ValueDraft -> Html Msg
viewValueDraftRow metrics i v =
    let
        metric =
            metrics |> List.drop i |> List.head

        labelText =
            if List.length metrics <= 1 then
                ""

            else
                metric |> Maybe.map .name |> Maybe.withDefault ""

        unitText =
            metric |> Maybe.map (.unit >> abbrevUnit) |> Maybe.withDefault ""
    in
    div
        [ class "entry-row"
        , style "display" "flex"
        , style "gap" "0.5rem"
        , style "align-items" "center"
        , style "margin-bottom" "0.25rem"
        ]
        ((if String.isEmpty labelText then
            []

          else
            [ div
                [ style "flex" "0 0 auto"
                , style "min-width" "7rem"
                , style "color" "#555"
                ]
                [ text labelText ]
            ]
         )
            ++ [ input
                    [ type_ "number"
                    , step "any"
                    , placeholder unitText
                    , value v.qty
                    , onInput (NewQtyChanged i)
                    , style "width" "7rem"
                    , style "flex" "0 0 auto"
                    ]
                    []
               , input
                    [ type_ "text"
                    , placeholder "note (optional)"
                    , value v.desc
                    , onInput (NewDescChanged i)
                    , style "flex" "1 1 auto"
                    , style "min-width" "0"
                    ]
                    []
               ]
        )


viewEntryRow : List Metric -> Maybe EditDraft -> Entry -> Html Msg
viewEntryRow metrics editing e =
    case editing of
        Just d ->
            if d.entryId == e.id then
                viewEditRow metrics e d

            else
                viewReadRow metrics e

        Nothing ->
            viewReadRow metrics e


viewReadRow : List Metric -> Entry -> Html Msg
viewReadRow metrics e =
    let
        isSkipped =
            List.all (\v -> v.quantity == 0 && String.isEmpty v.description) e.values

        renderValue i v =
            let
                unit =
                    metrics
                        |> List.drop i
                        |> List.head
                        |> Maybe.map (.unit >> abbrevUnit)
                        |> Maybe.withDefault ""
            in
            String.fromFloat v.quantity
                ++ (if String.isEmpty unit then
                        ""

                    else
                        " " ++ unit
                   )
                ++ (if String.isEmpty v.description then
                        ""

                    else
                        " — " ++ v.description
                   )

        body =
            if isSkipped then
                "(skipped)"

            else
                String.join " · " (List.indexedMap renderValue e.values)
    in
    div [ class "row" ]
        [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
        , div [ class "desc" ] [ text body ]
        , div [ class "ctrls" ]
            [ button [ onClick (StartEdit e) ] [ text "Edit" ]
            , button [ onClick (DeleteEntry e.id) ] [ text "Del" ]
            ]
        ]


viewEditRow : List Metric -> Entry -> EditDraft -> Html Msg
viewEditRow metrics e d =
    div [ class "row", style "flex-wrap" "wrap" ]
        [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
        , div
            [ style "display" "flex"
            , style "flex-direction" "column"
            , style "gap" "0.25rem"
            , style "flex" "1 1 auto"
            , style "min-width" "0"
            ]
            (List.indexedMap (viewEditValueRow metrics) d.values)
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


viewEditValueRow : List Metric -> Int -> ValueDraft -> Html Msg
viewEditValueRow metrics i v =
    let
        metric =
            metrics |> List.drop i |> List.head

        labelText =
            if List.length metrics <= 1 then
                ""

            else
                metric |> Maybe.map .name |> Maybe.withDefault ""

        unitText =
            metric |> Maybe.map (.unit >> abbrevUnit) |> Maybe.withDefault ""
    in
    div
        [ style "display" "flex"
        , style "gap" "0.5rem"
        , style "align-items" "center"
        ]
        ((if String.isEmpty labelText then
            []

          else
            [ div
                [ style "flex" "0 0 auto"
                , style "min-width" "7rem"
                , style "color" "#555"
                , style "font-size" "0.85rem"
                ]
                [ text labelText ]
            ]
         )
            ++ [ input
                    [ type_ "number"
                    , step "any"
                    , placeholder unitText
                    , value v.qty
                    , onInput (EditQtyChanged i)
                    , style "width" "6rem"
                    , style "flex" "0 0 auto"
                    ]
                    []
               , input
                    [ value v.desc
                    , onInput (EditDescChanged i)
                    , placeholder "note (optional)"
                    , style "flex" "1 1 auto"
                    , style "min-width" "0"
                    ]
                    []
               ]
        )
