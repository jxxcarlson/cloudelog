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


type alias EditDraft =
    { entryId : String
    , qty : String
    , desc : String
    , submitting : Bool
    }


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
    , editing : Maybe EditDraft
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
      , editing = Nothing
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
    | StartEdit Entry
    | EditQtyChanged String
    | EditDescChanged String
    | SaveEdit
    | CancelEdit
    | EditSaved (Result Http.Error Entry)


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
            , Cmd.none
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
                , div []
                    (List.map
                        (viewEntryRow model.editing)
                        (List.reverse (List.sortBy (Date.toRataDie << .date) model.entries))
                    )
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
