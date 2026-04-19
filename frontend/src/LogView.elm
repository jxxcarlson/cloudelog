module LogView exposing (Model, Msg(..), OutMsg(..), Stats, computeStats, init, update, view)

import Api
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Types exposing (Entry, Log, Unit(..), unitToString)



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


type alias Model =
    { logId : String
    , today : Date
    , log : Maybe Log
    , entries : List Entry
    , loading : Bool
    , error : Maybe String
    , newQty : String
    , newDesc : String
    , submitting : Bool
    }


init : String -> Date -> ( Model, Cmd Msg )
init logId today =
    ( { logId = logId
      , today = today
      , log = Nothing
      , entries = []
      , loading = True
      , error = Nothing
      , newQty = ""
      , newDesc = ""
      , submitting = False
      }
    , Api.getLog logId LogFetched
    )


type Msg
    = LogFetched (Result Http.Error { log : Log, entries : List Entry })
    | QtyChanged String
    | DescChanged String
    | AddEntry
    | EntryPosted (Result Http.Error (List Entry))
    | DeleteEntry String
    | EntryDeleted String (Result Http.Error ())


type OutMsg
    = NoOp


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        LogFetched (Ok { log, entries }) ->
            ( { model | log = Just log, entries = entries, loading = False, error = Nothing }
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
            , Cmd.none
            , NoOp
            )

        EntryPosted (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }, Cmd.none, NoOp )

        DeleteEntry eid ->
            ( model, Api.deleteEntry eid (EntryDeleted eid), NoOp )

        EntryDeleted eid (Ok ()) ->
            ( { model | entries = List.filter (\e -> e.id /= eid) model.entries }, Cmd.none, NoOp )

        EntryDeleted _ (Err err) ->
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
                    computeStats model.entries model.today
            in
            div []
                [ h1 [] [ text log.name ]
                , p []
                    [ text ("Unit: " ++ unitToString log.unit)
                    , text (" · since " ++ Date.toIsoString log.startDate)
                    ]
                , viewStats stats
                , if String.isEmpty log.description then
                    text ""

                  else
                    p [ style "color" "#555" ] [ text log.description ]
                , viewAddForm model
                , case model.error of
                    Just e ->
                        div [ class "flash" ] [ text e ]

                    Nothing ->
                        text ""
                , div [] (List.map viewEntryRow (List.reverse (List.sortBy (Date.toRataDie << .date) model.entries)))
                ]


viewStats : Stats -> Html msg
viewStats s =
    let
        fmt : Float -> String
        fmt n =
            String.fromFloat n

        maybeFmt : Maybe Float -> String
        maybeFmt =
            Maybe.map fmt >> Maybe.withDefault "—"
    in
    div [ class "stats" ]
        [ div [] [ text ("Days: " ++ String.fromInt s.days) ]
        , div [] [ text ("Skipped: " ++ String.fromInt s.skipped) ]
        , div [] [ text ("Total: " ++ fmt s.total) ]
        , div [] [ text ("Avg: " ++ maybeFmt s.average) ]
        ]


viewAddForm : Model -> Html Msg
viewAddForm m =
    Html.form [ onSubmit AddEntry ]
        [ input [ type_ "number", step "any", placeholder "quantity", value m.newQty, onInput QtyChanged ] []
        , input [ placeholder "note (optional)", value m.newDesc, onInput DescChanged ] []
        , button [ type_ "submit", class "primary", disabled m.submitting ]
            [ text
                (if m.submitting then
                    "Adding…"

                 else
                    "Add"
                )
            ]
        ]


viewEntryRow : Entry -> Html Msg
viewEntryRow e =
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
            [ button [ onClick (DeleteEntry e.id) ] [ text "Del" ] ]
        ]
