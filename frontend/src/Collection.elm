module Collection exposing (Model, Msg, OutMsg(..), computeCombinedTotals, init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Collection, CollectionDetail, CollectionMember, CombinedTotal, Device(..), Entry, Log, Metric)


type alias ValueDraft =
    { qty : String, desc : String }


type alias LogDraft =
    { logId : String, values : List ValueDraft }


type alias EditDraft =
    { entryId : String
    , values : List ValueDraft
    , submitting : Bool
    }


type alias Model =
    { collectionId : String
    , today : Date
    , detail : Maybe CollectionDetail
    , loading : Bool
    , error : Maybe String
    , drafts : List LogDraft
    , submitting : Bool
    , editing : Maybe EditDraft
    }


type Msg
    = DetailFetched (Result Http.Error CollectionDetail)
    | OpenLog String
    | DraftQtyChanged String Int String
    | DraftDescChanged String Int String
    | SubmitCombined
    | CombinedPosted (Result Http.Error CollectionDetail)
    | StartEdit Entry
    | EditQtyChanged Int String
    | EditDescChanged Int String
    | SaveEdit
    | CancelEdit
    | EditSaved (Result Http.Error Entry)


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
      , editing = Nothing
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
                , editing = Nothing
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
                , editing = Nothing
              }
            , Cmd.none
            , NoOp
            )

        CombinedPosted (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }
            , Cmd.none
            , NoOp
            )

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
                                    if String.isEmpty (String.trim v.qty) then
                                        Just { quantity = 0, description = v.desc }

                                    else
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

        EditSaved (Ok _) ->
            ( model
            , Api.getCollection model.collectionId DetailFetched
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


view : Device -> Model -> Html Msg
view device model =
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
            let
                totals =
                    computeCombinedTotals model.today d.members
            in
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
                , viewCombinedTotals totals
                , viewPerLog d.members
                , viewHistory d.members
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
                    if List.length metrics <= 1 then
                        logName

                    else
                        logName ++ " — " ++ mm.name

                Nothing ->
                    logName

        unitText =
            metric |> Maybe.map (.unit >> abbrevUnit) |> Maybe.withDefault ""
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
            , placeholder unitText
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


computeCombinedTotals : Date -> List CollectionMember -> List CombinedTotal
computeCombinedTotals today members =
    let
        -- All (unit, quantity, date) tuples from every (log, metric) pair.
        allContributions : List ( String, Float, Date )
        allContributions =
            members
                |> List.concatMap
                    (\m ->
                        List.concatMap
                            (\e ->
                                List.map2
                                    (\metric v -> ( metric.unit, v.quantity, e.date ))
                                    m.log.metrics
                                    e.values
                            )
                            m.entries
                    )

        contributions : List ( String, Float, Date )
        contributions =
            List.filter (\( _, q, _ ) -> q > 0) allContributions

        -- For each unit, count how many distinct (log, metric) pairs
        -- feed it across the collection.
        contributorsByUnit : List ( String, Int )
        contributorsByUnit =
            members
                |> List.concatMap (\m -> List.map .unit m.log.metrics)
                |> groupCount

        -- Group positive contributions by unit.
        byUnit : List ( String, List ( Float, Date ) )
        byUnit =
            groupBy (List.map (\( u, q, d ) -> ( u, ( q, d ) )) contributions)

        -- Distinct zero-contribution dates per unit (any quantity == 0).
        zeroDatesByUnit : List ( String, List Int )
        zeroDatesByUnit =
            allContributions
                |> List.filter (\( _, q, _ ) -> q == 0)
                |> List.map (\( u, _, d ) -> ( u, Date.toRataDie d ))
                |> groupBy
                |> List.map (\( u, ds ) -> ( u, dedup ds ))
    in
    List.filterMap
        (\( unit, pairs ) ->
            let
                contributors =
                    contributorsByUnit
                        |> List.filter (\( u, _ ) -> u == unit)
                        |> List.head
                        |> Maybe.map Tuple.second
                        |> Maybe.withDefault 0

                total =
                    pairs |> List.map Tuple.first |> List.sum

                positiveDays =
                    pairs
                        |> List.map (Tuple.second >> Date.toRataDie)
                        |> dedup

                distinctDays =
                    List.length positiveDays

                zeroDays =
                    zeroDatesByUnit
                        |> List.filter (\( u, _ ) -> u == unit)
                        |> List.head
                        |> Maybe.map Tuple.second
                        |> Maybe.withDefault []

                skippedDays =
                    List.length (List.filter (\d -> not (List.member d positiveDays)) zeroDays)

                streakRuns =
                    consecutiveRuns (List.sort positiveDays)

                longestStreak =
                    streakRuns |> List.map .length |> List.maximum |> Maybe.withDefault 0

                todayRD =
                    Date.toRataDie today

                currentStreak =
                    case List.reverse streakRuns of
                        last :: _ ->
                            if last.endRD >= todayRD - 1 then
                                last.length

                            else
                                0

                        [] ->
                            0

                average =
                    if distinctDays > 0 then
                        Just (total / toFloat distinctDays)

                    else
                        Nothing
            in
            if contributors >= 2 then
                Just
                    { unit = unit
                    , total = total
                    , average = average
                    , days = distinctDays
                    , skipped = skippedDays
                    , currentStreak = currentStreak
                    , longestStreak = longestStreak
                    , contributors = contributors
                    }

            else
                Nothing
        )
        byUnit


{-| Group sorted unique day-numbers into runs of consecutive integers.
Each run records its end-day (Rata Die) and length so callers can both
report the longest run and decide whether the most recent run is the
"current" streak.
-}
consecutiveRuns : List Int -> List { endRD : Int, length : Int }
consecutiveRuns sortedDays =
    case sortedDays of
        [] ->
            []

        first :: rest ->
            let
                step d acc =
                    case acc of
                        cur :: older ->
                            if d == cur.endRD + 1 then
                                { endRD = d, length = cur.length + 1 } :: older

                            else
                                { endRD = d, length = 1 } :: acc

                        [] ->
                            [ { endRD = d, length = 1 } ]
            in
            List.foldl step [ { endRD = first, length = 1 } ] rest
                |> List.reverse


groupBy : List ( comparable, b ) -> List ( comparable, List b )
groupBy xs =
    List.foldl
        (\( k, v ) acc ->
            if List.any (\( ka, _ ) -> ka == k) acc then
                List.map
                    (\( ka, vs ) ->
                        if ka == k then
                            ( ka, vs ++ [ v ] )

                        else
                            ( ka, vs )
                    )
                    acc

            else
                acc ++ [ ( k, [ v ] ) ]
        )
        []
        xs


groupCount : List comparable -> List ( comparable, Int )
groupCount =
    List.foldl
        (\x acc ->
            if List.any (\( k, _ ) -> k == x) acc then
                List.map
                    (\( k, n ) ->
                        if k == x then
                            ( k, n + 1 )

                        else
                            ( k, n )
                    )
                    acc

            else
                acc ++ [ ( x, 1 ) ]
        )
        []


dedup : List comparable -> List comparable
dedup xs =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []
        xs


viewCombinedTotals : List CombinedTotal -> Html Msg
viewCombinedTotals totals =
    if List.isEmpty totals then
        text ""

    else
        div []
            [ h3 [] [ text "Combined totals" ]
            , div []
                (List.map
                    (\t ->
                        div [ class "stats" ]
                            [ div [] [ text (String.fromInt t.days ++ " days") ]
                            , div [] [ text (String.fromInt t.skipped ++ " skipped") ]
                            , div [] [ text (fmtTotal t.unit t.total) ]
                            , div []
                                [ text
                                    ("avg "
                                        ++ (case t.average of
                                                Just a ->
                                                    fmt1 a ++ " " ++ abbrevUnit t.unit ++ "/day"

                                                Nothing ->
                                                    "—"
                                           )
                                    )
                                ]
                            , div [] [ text ("current streak: " ++ String.fromInt t.currentStreak) ]
                            , div [] [ text ("longest streak: " ++ String.fromInt t.longestStreak) ]
                            ]
                    )
                    totals
                )
            ]


viewPerLog : List CollectionMember -> Html Msg
viewPerLog members =
    div []
        [ h3 [] [ text "Per log" ]
        , div [] (List.map viewPerLogRow members)
        ]


viewPerLogRow : CollectionMember -> Html Msg
viewPerLogRow m =
    let
        days =
            List.length m.entries

        skipped =
            List.length
                (List.filter
                    (\e -> List.all (\v -> v.quantity == 0) e.values)
                    m.entries
                )

        statsText =
            "Days: "
                ++ String.fromInt days
                ++ " · Skipped: "
                ++ String.fromInt skipped
                ++ " · Current streak: "
                ++ String.fromInt m.streakStats.current
                ++ " · Longest streak: "
                ++ String.fromInt m.streakStats.longest
    in
    div
        [ class "row"
        , style "cursor" "pointer"
        , onClick (OpenLog m.log.id)
        ]
        [ div [ class "desc" ]
            [ strong [] [ text m.log.name ]
            , span [ style "color" "#666" ] [ text (" — " ++ statsText) ]
            ]
        ]


type alias HistoryRow =
    { date : Date
    , logName : String
    , metrics : List Metric
    , entry : Entry
    }


viewHistory : List CollectionMember -> Html Msg
viewHistory members =
    let
        rows : List HistoryRow
        rows =
            members
                |> List.concatMap
                    (\m ->
                        List.map
                            (\e ->
                                { date = e.date
                                , logName = m.log.name
                                , metrics = m.log.metrics
                                , entry = e
                                }
                            )
                            m.entries
                    )
                |> List.sortBy (\r -> -(Date.toRataDie r.date))

        groups : List ( Date, List HistoryRow )
        groups =
            rows
                |> List.foldr
                    (\r acc ->
                        case acc of
                            ( da, xs ) :: rest ->
                                if Date.toRataDie da == Date.toRataDie r.date then
                                    ( da, r :: xs ) :: rest

                                else
                                    ( r.date, [ r ] ) :: acc

                            [] ->
                                [ ( r.date, [ r ] ) ]
                    )
                    []
    in
    if List.isEmpty groups then
        text ""

    else
        div []
            [ h3 [] [ text "History" ]
            , div [] (List.map viewHistoryDay groups)
            ]


viewHistoryDay : ( Date, List HistoryRow ) -> Html Msg
viewHistoryDay ( date, rows ) =
    div [ style "margin" "0.75rem 0" ]
        (h4 [] [ text (Date.toIsoString date) ]
            :: List.map viewHistoryRow rows
        )


viewHistoryRow : HistoryRow -> Html Msg
viewHistoryRow { logName, metrics, entry } =
    let
        isSkip =
            List.all (\v -> v.quantity == 0 && String.isEmpty v.description) entry.values

        rendered =
            if isSkip then
                "(skipped)"

            else
                List.indexedMap
                    (\i v ->
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
                    )
                    entry.values
                    |> String.join " · "
    in
    div
        [ style "display" "flex"
        , style "gap" "1rem"
        , style "padding" "0.2rem 0"
        ]
        [ div [ style "min-width" "10rem", style "color" "#555" ] [ text logName ]
        , div [] [ text rendered ]
        ]


fmt : Float -> String
fmt =
    String.fromFloat


fmtTotal : String -> Float -> String
fmtTotal unit total =
    case unit of
        "minutes" ->
            if total >= 60 then
                let
                    totalMin =
                        round total

                    h =
                        totalMin // 60

                    m =
                        modBy 60 totalMin
                in
                if m == 0 then
                    "Total " ++ String.fromInt h ++ "h"

                else
                    "Total " ++ String.fromInt h ++ "h " ++ String.fromInt m ++ "m"

            else
                "Total " ++ fmt total ++ " min"

        _ ->
            "Total " ++ fmt total ++ " " ++ abbrevUnit unit


fmt1 : Float -> String
fmt1 a =
    String.fromFloat (toFloat (round (a * 10)) / 10)


abbrevUnit : String -> String
abbrevUnit unit =
    case unit of
        "minutes" ->
            "min"

        _ ->
            unit
