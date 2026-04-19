module LogList exposing (Model, Msg(..), OutMsg(..), init, update, view)

import Api
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Log, LogSummary, Unit(..), unitToString)


type alias NewLogForm =
    { open : Bool
    , name : String
    , unitChoice : String
    , customUnit : String
    , description : String
    , startDate : String
    }


emptyForm : NewLogForm
emptyForm =
    { open = False
    , name = ""
    , unitChoice = "minutes"
    , customUnit = ""
    , description = ""
    , startDate = ""
    }


type alias Model =
    { logs : List LogSummary
    , loading : Bool
    , error : Maybe String
    , form : NewLogForm
    , pendingDelete : Maybe String
    }


init : ( Model, Cmd Msg )
init =
    ( { logs = []
      , loading = True
      , error = Nothing
      , form = emptyForm
      , pendingDelete = Nothing
      }
    , Api.listLogs LogsFetched
    )


type Msg
    = LogsFetched (Result Http.Error (List LogSummary))
    | OpenNewForm
    | CloseNewForm
    | NameChanged String
    | UnitChoiceChanged String
    | CustomUnitChanged String
    | DescriptionChanged String
    | StartDateChanged String
    | SubmitNew
    | LogCreated (Result Http.Error Log)
    | OpenLog String
    | AskDelete String
    | CancelDelete
    | ConfirmDelete String
    | LogDeleted String (Result Http.Error ())


type OutMsg
    = NoOp
    | NavigateToLog String


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        LogsFetched (Ok logs) ->
            ( { model | logs = logs, loading = False, error = Nothing }, Cmd.none, NoOp )

        LogsFetched (Err err) ->
            ( { model | loading = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        OpenNewForm ->
            ( { model | form = { emptyForm | open = True } }, Cmd.none, NoOp )

        CloseNewForm ->
            ( { model | form = emptyForm }, Cmd.none, NoOp )

        NameChanged s ->
            ( { model | form = updForm model.form (\f -> { f | name = s }) }, Cmd.none, NoOp )

        UnitChoiceChanged s ->
            ( { model | form = updForm model.form (\f -> { f | unitChoice = s }) }, Cmd.none, NoOp )

        CustomUnitChanged s ->
            ( { model | form = updForm model.form (\f -> { f | customUnit = s }) }, Cmd.none, NoOp )

        DescriptionChanged s ->
            ( { model | form = updForm model.form (\f -> { f | description = s }) }, Cmd.none, NoOp )

        StartDateChanged s ->
            ( { model | form = updForm model.form (\f -> { f | startDate = s }) }, Cmd.none, NoOp )

        SubmitNew ->
            let
                f =
                    model.form

                unit =
                    if f.unitChoice == "custom" then
                        String.trim f.customUnit

                    else
                        f.unitChoice
            in
            if String.isEmpty (String.trim f.name) || String.isEmpty unit then
                ( { model | error = Just "Name and unit are required." }, Cmd.none, NoOp )

            else
                let
                    startDate =
                        if String.isEmpty (String.trim f.startDate) then
                            Nothing

                        else
                            Just (String.trim f.startDate)
                in
                ( model
                , Api.createLog
                    { name = String.trim f.name
                    , unit = unit
                    , description = f.description
                    , startDate = startDate
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
                    , unit = log.unit
                    , description = log.description
                    , startDate = log.startDate
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


view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Your logs" ]
        , case model.error of
            Just e ->
                div [ class "flash" ] [ text e ]

            Nothing ->
                text ""
        , if model.form.open then
            viewForm model.form

          else
            button [ class "primary", onClick OpenNewForm ] [ text "+ New log" ]
        , div [] (List.map (viewRow model) model.logs)
        , if model.loading then
            p [] [ text "Loading..." ]

          else if List.isEmpty model.logs && not model.form.open then
            p [] [ text "No logs yet. Create one above." ]

          else
            text ""
        ]


viewForm : NewLogForm -> Html Msg
viewForm f =
    Html.form [ onSubmit SubmitNew ]
        [ input [ placeholder "Name (e.g. Running)", value f.name, onInput NameChanged ] []
        , select [ onInput UnitChoiceChanged ]
            [ option [ value "minutes", selected (f.unitChoice == "minutes") ] [ text "Minutes" ]
            , option [ value "hours", selected (f.unitChoice == "hours") ] [ text "Hours" ]
            , option [ value "kilometers", selected (f.unitChoice == "kilometers") ] [ text "Kilometers" ]
            , option [ value "miles", selected (f.unitChoice == "miles") ] [ text "Miles" ]
            , option [ value "custom", selected (f.unitChoice == "custom") ] [ text "Custom…" ]
            ]
        , if f.unitChoice == "custom" then
            input [ placeholder "unit name", value f.customUnit, onInput CustomUnitChanged ] []

          else
            text ""
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


viewRow : Model -> LogSummary -> Html Msg
viewRow model l =
    div [ class "row" ]
        [ div [ class "desc", onClick (OpenLog l.id), style "cursor" "pointer" ]
            [ strong [] [ text l.name ]
            , text (" — " ++ unitToString l.unit)
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
