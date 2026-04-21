module LogList exposing (Model, Msg(..), OutMsg(..), init, update, view)

import Api
import Date
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Collection, CollectionSummary, Log, LogSummary, Metric)


type alias MetricDraft =
    { name : String
    , unit : String
    }


type alias NewLogForm =
    { open : Bool
    , name : String
    , metrics : List MetricDraft
    , description : String
    , startDate : String
    }


emptyForm : NewLogForm
emptyForm =
    { open = False
    , name = ""
    , metrics = [ { name = "", unit = "" } ]
    , description = ""
    , startDate = ""
    }


type alias NewCollectionForm =
    { open : Bool
    , name : String
    , description : String
    }


emptyCollectionForm : NewCollectionForm
emptyCollectionForm =
    { open = False, name = "", description = "" }


type alias Model =
    { logs : List LogSummary
    , collections : List CollectionSummary
    , loading : Bool
    , error : Maybe String
    , form : NewLogForm
    , collectionForm : NewCollectionForm
    , pendingDelete : Maybe String
    }


init : ( Model, Cmd Msg )
init =
    ( { logs = []
      , collections = []
      , loading = True
      , error = Nothing
      , form = emptyForm
      , collectionForm = emptyCollectionForm
      , pendingDelete = Nothing
      }
    , Cmd.batch
        [ Api.listLogs LogsFetched
        , Api.listCollections CollectionsFetched
        ]
    )


type Msg
    = LogsFetched (Result Http.Error (List LogSummary))
    | CollectionsFetched (Result Http.Error (List CollectionSummary))
    | OpenNewForm
    | CloseNewForm
    | NameChanged String
    | MetricNameChanged Int String
    | MetricUnitChanged Int String
    | AddMetricRow
    | RemoveMetricRow Int
    | DescriptionChanged String
    | StartDateChanged String
    | SubmitNewLog
    | LogCreated (Result Http.Error Log)
    | OpenLog String
    | OpenCollection String
    | OpenNewCollection
    | CloseNewCollection
    | CollNameChanged String
    | CollDescriptionChanged String
    | SubmitNewCollection
    | CollectionCreated (Result Http.Error Collection)
    | AskDelete String
    | CancelDelete
    | ConfirmDelete String
    | LogDeleted String (Result Http.Error ())


type OutMsg
    = NoOp
    | NavigateToLog String
    | NavigateToCollection String


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        LogsFetched (Ok logs) ->
            ( { model | logs = logs, loading = False, error = Nothing }, Cmd.none, NoOp )

        LogsFetched (Err err) ->
            ( { model | loading = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        CollectionsFetched (Ok cs) ->
            ( { model | collections = cs }, Cmd.none, NoOp )

        CollectionsFetched (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        OpenNewForm ->
            ( { model | form = { emptyForm | open = True } }, Cmd.none, NoOp )

        CloseNewForm ->
            ( { model | form = emptyForm }, Cmd.none, NoOp )

        NameChanged s ->
            ( { model | form = updForm model.form (\f -> { f | name = s }) }, Cmd.none, NoOp )

        MetricNameChanged i s ->
            ( { model | form = updForm model.form (\f -> { f | metrics = updateAt i (\m -> { m | name = s }) f.metrics }) }
            , Cmd.none
            , NoOp
            )

        MetricUnitChanged i s ->
            ( { model | form = updForm model.form (\f -> { f | metrics = updateAt i (\m -> { m | unit = s }) f.metrics }) }
            , Cmd.none
            , NoOp
            )

        AddMetricRow ->
            ( { model | form = updForm model.form (\f -> { f | metrics = f.metrics ++ [ { name = "", unit = "" } ] }) }
            , Cmd.none
            , NoOp
            )

        RemoveMetricRow i ->
            ( { model | form = updForm model.form (\f -> { f | metrics = removeAt i f.metrics }) }
            , Cmd.none
            , NoOp
            )

        DescriptionChanged s ->
            ( { model | form = updForm model.form (\f -> { f | description = s }) }, Cmd.none, NoOp )

        StartDateChanged s ->
            ( { model | form = updForm model.form (\f -> { f | startDate = s }) }, Cmd.none, NoOp )

        SubmitNewLog ->
            let
                f =
                    model.form

                metrics : List Metric
                metrics =
                    List.map (\m -> { name = String.trim m.name, unit = String.trim m.unit }) f.metrics
            in
            if String.isEmpty (String.trim f.name) then
                ( { model | error = Just "Name is required." }, Cmd.none, NoOp )

            else if List.isEmpty metrics || List.any (\m -> String.isEmpty m.name || String.isEmpty m.unit) metrics then
                ( { model | error = Just "Each metric needs a name and a unit." }, Cmd.none, NoOp )

            else
                ( model
                , Api.createLog
                    { name = String.trim f.name
                    , metrics = metrics
                    , description = f.description
                    , startDate =
                        if String.isEmpty (String.trim f.startDate) then
                            Nothing

                        else
                            Date.fromIsoString f.startDate |> Result.toMaybe
                    }
                    LogCreated
                , NoOp
                )

        LogCreated (Ok log) ->
            let
                summary : LogSummary
                summary =
                    { id = log.id
                    , name = log.name
                    , metrics = log.metrics
                    , description = log.description
                    , startDate = log.startDate
                    , collectionId = log.collectionId
                    , createdAt = log.createdAt
                    , updatedAt = log.updatedAt
                    }
            in
            ( { model | logs = summary :: model.logs, form = emptyForm, error = Nothing }
            , Cmd.none
            , NoOp
            )

        LogCreated (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        OpenLog id ->
            ( model, Cmd.none, NavigateToLog id )

        OpenCollection id ->
            ( model, Cmd.none, NavigateToCollection id )

        OpenNewCollection ->
            ( { model | collectionForm = { emptyCollectionForm | open = True } }, Cmd.none, NoOp )

        CloseNewCollection ->
            ( { model | collectionForm = emptyCollectionForm }, Cmd.none, NoOp )

        CollNameChanged s ->
            ( { model | collectionForm = updCollectionForm model.collectionForm (\f -> { f | name = s }) }
            , Cmd.none
            , NoOp
            )

        CollDescriptionChanged s ->
            ( { model | collectionForm = updCollectionForm model.collectionForm (\f -> { f | description = s }) }
            , Cmd.none
            , NoOp
            )

        SubmitNewCollection ->
            let
                f =
                    model.collectionForm
            in
            if String.isEmpty (String.trim f.name) then
                ( { model | error = Just "Collection name is required." }, Cmd.none, NoOp )

            else
                ( model
                , Api.createCollection
                    { name = String.trim f.name, description = f.description }
                    CollectionCreated
                , NoOp
                )

        CollectionCreated (Ok _) ->
            ( { model | collectionForm = emptyCollectionForm, error = Nothing }
            , Api.listCollections CollectionsFetched
            , NoOp
            )

        CollectionCreated (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        AskDelete id ->
            ( { model | pendingDelete = Just id }, Cmd.none, NoOp )

        CancelDelete ->
            ( { model | pendingDelete = Nothing }, Cmd.none, NoOp )

        ConfirmDelete id ->
            ( { model | pendingDelete = Nothing }
            , Api.deleteLog id (LogDeleted id)
            , NoOp
            )

        LogDeleted id (Ok ()) ->
            ( { model | logs = List.filter (\l -> l.id /= id) model.logs }, Cmd.none, NoOp )

        LogDeleted _ (Err err) ->
            ( { model | error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )


updForm : NewLogForm -> (NewLogForm -> NewLogForm) -> NewLogForm
updForm f g =
    g f


updCollectionForm : NewCollectionForm -> (NewCollectionForm -> NewCollectionForm) -> NewCollectionForm
updCollectionForm f g =
    g f


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


removeAt : Int -> List a -> List a
removeAt i xs =
    List.indexedMap Tuple.pair xs
        |> List.filter (\( j, _ ) -> j /= i)
        |> List.map Tuple.second


view : Model -> Html Msg
view model =
    let
        standaloneLogs =
            List.filter (\l -> l.collectionId == Nothing) model.logs
    in
    div []
        [ h1 [] [ text "Your logs" ]
        , case model.error of
            Just e ->
                div [ class "flash" ] [ text e ]

            Nothing ->
                text ""
        , viewActionButtons model
        , if model.form.open then
            viewForm model.form

          else
            text ""
        , if model.collectionForm.open then
            viewCollectionForm model.collectionForm

          else
            text ""
        , viewCollections model.collections
        , h3 [] [ text "Logs" ]
        , div [] (List.map (viewRow model) standaloneLogs)
        , if model.loading then
            p [] [ text "Loading..." ]

          else if List.isEmpty standaloneLogs && not model.form.open then
            p [] [ text "No logs yet. Create one above." ]

          else
            text ""
        ]


viewActionButtons : Model -> Html Msg
viewActionButtons model =
    div [ style "display" "flex", style "gap" "0.5rem", style "margin-bottom" "0.75rem" ]
        [ if model.form.open then
            text ""

          else
            button [ class "primary", onClick OpenNewForm ] [ text "+ New log" ]
        , if model.collectionForm.open then
            text ""

          else
            button [ onClick OpenNewCollection ] [ text "+ New collection" ]
        ]


viewCollections : List CollectionSummary -> Html Msg
viewCollections cs =
    if List.isEmpty cs then
        text ""

    else
        div []
            [ h3 [] [ text "Collections" ]
            , div [] (List.map viewCollectionRow cs)
            ]


viewCollectionRow : CollectionSummary -> Html Msg
viewCollectionRow c =
    div
        [ class "row"
        , onClick (OpenCollection c.id)
        , style "cursor" "pointer"
        ]
        [ div [ class "desc" ]
            [ strong [] [ text c.name ]
            , text
                (" — "
                    ++ String.fromInt c.memberCount
                    ++ (if c.memberCount == 1 then
                            " log"

                        else
                            " logs"
                       )
                )
            , if String.isEmpty c.description then
                text ""

              else
                div [ style "color" "#555", style "font-size" "0.9rem" ] [ text c.description ]
            ]
        ]


viewForm : NewLogForm -> Html Msg
viewForm f =
    Html.form [ onSubmit SubmitNewLog ]
        [ input [ placeholder "Name (e.g. Running)", value f.name, onInput NameChanged ] []
        , viewMetricsEditor f.metrics
        , input [ placeholder "description (optional)", value f.description, onInput DescriptionChanged ] []
        , input
            [ type_ "date"
            , value f.startDate
            , onInput StartDateChanged
            , attribute "aria-label" "start date (optional, defaults to today)"
            ]
            []
        , button [ type_ "submit", class "primary" ] [ text "Create" ]
        , button [ type_ "button", onClick CloseNewForm ] [ text "Cancel" ]
        ]


viewCollectionForm : NewCollectionForm -> Html Msg
viewCollectionForm f =
    Html.form [ onSubmit SubmitNewCollection ]
        [ input
            [ placeholder "Collection name (e.g. Fitness)"
            , value f.name
            , onInput CollNameChanged
            ]
            []
        , input
            [ placeholder "description (optional)"
            , value f.description
            , onInput CollDescriptionChanged
            ]
            []
        , button [ type_ "submit", class "primary" ] [ text "Create collection" ]
        , button [ type_ "button", onClick CloseNewCollection ] [ text "Cancel" ]
        ]


viewMetricRow : Int -> Int -> MetricDraft -> Html Msg
viewMetricRow total i m =
    div
        [ class "metric-row"
        , style "display" "flex"
        , style "gap" "0.5rem"
        , style "align-items" "center"
        , style "margin-bottom" "0.25rem"
        ]
        [ input
            [ placeholder "metric name (e.g. distance)"
            , value m.name
            , onInput (MetricNameChanged i)
            , style "flex" "1 1 auto"
            , style "min-width" "0"
            ]
            []
        , input
            [ placeholder "unit (e.g. miles)"
            , value m.unit
            , onInput (MetricUnitChanged i)
            , style "flex" "0 0 auto"
            , style "width" "10rem"
            ]
            []
        , button
            [ onClick (RemoveMetricRow i)
            , disabled (total <= 1)
            , type_ "button"
            , style "flex" "0 0 auto"
            ]
            [ text "Remove" ]
        ]


viewMetricsEditor : List MetricDraft -> Html Msg
viewMetricsEditor metrics =
    let
        total =
            List.length metrics
    in
    div []
        (List.indexedMap (viewMetricRow total) metrics
            ++ [ button [ onClick AddMetricRow, type_ "button" ] [ text "+ Add metric" ] ]
        )


viewRow : Model -> LogSummary -> Html Msg
viewRow model l =
    div [ class "row" ]
        [ div [ class "desc", onClick (OpenLog l.id), style "cursor" "pointer" ]
            [ strong [] [ text l.name ]
            , text (" — " ++ metricsLabel l.metrics)
            , if String.isEmpty l.description then
                text ""

              else
                span [ style "color" "#666" ] [ text (" · " ++ l.description) ]
            ]
        , div [ class "ctrls" ]
            [ case model.pendingDelete of
                Just pid ->
                    if pid == l.id then
                        span []
                            [ text "Delete? "
                            , button [ onClick (ConfirmDelete l.id) ] [ text "Yes" ]
                            , button [ onClick CancelDelete ] [ text "Cancel" ]
                            ]

                    else
                        button [ onClick (AskDelete l.id) ] [ text "Delete" ]

                Nothing ->
                    button [ onClick (AskDelete l.id) ] [ text "Delete" ]
            ]
        ]


metricsLabel : List Metric -> String
metricsLabel metrics =
    case metrics of
        [ m ] ->
            if m.name == m.unit then
                m.unit

            else
                m.name ++ " (" ++ m.unit ++ ")"

        _ ->
            metrics
                |> List.map (\m -> m.name ++ " (" ++ m.unit ++ ")")
                |> String.join ", "
