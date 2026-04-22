module Main exposing (main)

import Api
import Auth
import Browser
import Browser.Navigation as Nav
import Collection
import Date exposing (Date)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Http
import LogList
import LogView
import Route exposing (Route(..))
import Task
import Time
import Browser.Dom
import Browser.Events
import Types exposing (Device(..), User, classify)
import Url exposing (Url)


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onResize (\w _ -> ViewportResized w)


type Page
    = PageLoading
    | PageAuth Auth.Model
    | PageLogList LogList.Model
    | PageLogView LogView.Model
    | PageCollection Collection.Model
    | PageNotFound


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , user : Maybe User
    , today : Maybe Date
    , flash : Maybe String
    , page : Page
    , device : Device
    }


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | GotToday Date
    | MeResponded (Result Http.Error User)
    | AuthMsg Auth.Msg
    | LogListMsg LogList.Msg
    | LogViewMsg LogView.Msg
    | CollectionMsg Collection.Msg
    | LogoutRequested
    | LogoutResponded (Result Http.Error ())
    | GotInitialViewport Browser.Dom.Viewport
    | ViewportResized Int


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , url = url
      , route = Route.fromUrl url
      , user = Nothing
      , today = Nothing
      , flash = Nothing
      , page = PageLoading
      , device = Desktop
      }
    , Cmd.batch
        [ Task.map2 (\zone time -> Date.fromPosix zone time) Time.here Time.now
            |> Task.perform GotToday
        , Api.me MeResponded
        , Task.perform GotInitialViewport Browser.Dom.getViewport
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked (Browser.Internal url) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        LinkClicked (Browser.External url) ->
            ( model, Nav.load url )

        UrlChanged url ->
            goto { model | url = url } (Route.fromUrl url)

        GotToday d ->
            ( { model | today = Just d }, Cmd.none )
                |> maybeTransition

        MeResponded (Ok user) ->
            let
                withUser =
                    { model | user = Just user }

                -- If the user just finished signing in, we're still on /login or /signup;
                -- bounce them to / so goto picks the LogList page.
                postAuthCmd =
                    case model.route of
                        Login ->
                            Nav.pushUrl model.key "/"

                        Signup ->
                            Nav.pushUrl model.key "/"

                        _ ->
                            Cmd.none
            in
            ( withUser, postAuthCmd ) |> maybeTransition

        MeResponded (Err _) ->
            -- Only act on this response while we're still on the loading
            -- screen (boot-time probe). If the user has already reached
            -- an auth page and started interacting, leave them alone —
            -- otherwise a late /me response clobbers mid-flight mode switches.
            case model.page of
                PageLoading ->
                    case model.route of
                        Login ->
                            ( { model | page = PageAuth (Auth.init Auth.LoginMode) }, Cmd.none )

                        Signup ->
                            ( { model | page = PageAuth (Auth.init Auth.SignupMode) }, Cmd.none )

                        _ ->
                            ( model, Nav.replaceUrl model.key "/login" )

                _ ->
                    ( model, Cmd.none )

        AuthMsg subMsg ->
            case model.page of
                PageAuth subModel ->
                    let
                        ( newSub, subCmd, outMsg ) =
                            Auth.update subMsg subModel
                    in
                    case outMsg of
                        Auth.AuthSucceeded ->
                            -- Fetch /me; the MeResponded branch handles the redirect.
                            ( { model | page = PageAuth newSub }
                            , Cmd.batch [ Cmd.map AuthMsg subCmd, Api.me MeResponded ]
                            )

                        Auth.NoOp ->
                            ( { model | page = PageAuth newSub }, Cmd.map AuthMsg subCmd )

                _ ->
                    ( model, Cmd.none )

        LogListMsg subMsg ->
            case model.page of
                PageLogList subModel ->
                    let
                        ( newSub, subCmd, outMsg ) =
                            LogList.update subMsg subModel

                        base =
                            ( { model | page = PageLogList newSub }, Cmd.map LogListMsg subCmd )
                    in
                    case outMsg of
                        LogList.NavigateToLog id ->
                            ( { model | page = PageLogList newSub }
                            , Cmd.batch [ Cmd.map LogListMsg subCmd, Nav.pushUrl model.key ("/logs/" ++ id) ]
                            )

                        LogList.NavigateToCollection id ->
                            ( { model | page = PageLogList newSub }
                            , Cmd.batch [ Cmd.map LogListMsg subCmd, Nav.pushUrl model.key ("/collections/" ++ id) ]
                            )

                        LogList.NoOp ->
                            base

                _ ->
                    ( model, Cmd.none )

        LogViewMsg subMsg ->
            case model.page of
                PageLogView subModel ->
                    let
                        ( newSub, subCmd, _ ) =
                            LogView.update subMsg subModel
                    in
                    ( { model | page = PageLogView newSub }, Cmd.map LogViewMsg subCmd )

                _ ->
                    ( model, Cmd.none )

        CollectionMsg subMsg ->
            case model.page of
                PageCollection subModel ->
                    let
                        ( newSub, subCmd, outMsg ) =
                            Collection.update subMsg subModel

                        navCmd =
                            case outMsg of
                                Collection.NavigateToLog logId ->
                                    Nav.pushUrl model.key ("/logs/" ++ logId)

                                Collection.NoOp ->
                                    Cmd.none
                    in
                    ( { model | page = PageCollection newSub }
                    , Cmd.batch [ Cmd.map CollectionMsg subCmd, navCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        LogoutRequested ->
            ( model, Api.logout LogoutResponded )

        LogoutResponded _ ->
            ( { model | user = Nothing, page = PageAuth (Auth.init Auth.LoginMode) }
            , Nav.pushUrl model.key "/login"
            )

        GotInitialViewport vp ->
            ( { model | device = classify (round vp.viewport.width) }
            , Cmd.none
            )

        ViewportResized w ->
            ( { model | device = classify w }
            , Cmd.none
            )



-- | After async boot events (GotToday, MeResponded) land, decide if we can
--   transition into a real page.
maybeTransition : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
maybeTransition ( model, cmd ) =
    case ( model.today, model.user ) of
        ( Just _, Just _ ) ->
            let
                ( newModel, newCmd ) =
                    goto model model.route
            in
            ( newModel, Cmd.batch [ cmd, newCmd ] )

        _ ->
            ( model, cmd )


goto : Model -> Route -> ( Model, Cmd Msg )
goto model route =
    let
        base =
            { model | route = route }

        currentEmail =
            case model.page of
                PageAuth auth ->
                    auth.email

                _ ->
                    ""
    in
    case ( route, model.user, model.today ) of
        ( Login, _, _ ) ->
            ( { base | page = PageAuth (Auth.initWithEmail Auth.LoginMode currentEmail) }, Cmd.none )

        ( Signup, _, _ ) ->
            ( { base | page = PageAuth (Auth.initWithEmail Auth.SignupMode currentEmail) }, Cmd.none )

        ( _, Nothing, _ ) ->
            ( base, Nav.pushUrl model.key "/login" )

        ( Home, Just _, _ ) ->
            let
                ( subModel, subCmd ) =
                    LogList.init
            in
            ( { base | page = PageLogList subModel }, Cmd.map LogListMsg subCmd )

        ( LogDetail id, Just _, Just today ) ->
            let
                ( subModel, subCmd ) =
                    LogView.init id today
            in
            ( { base | page = PageLogView subModel }, Cmd.map LogViewMsg subCmd )

        ( LogDetail _, Just _, Nothing ) ->
            -- Today not loaded yet; stay on Loading.
            ( { base | page = PageLoading }, Cmd.none )

        ( CollectionDetail id, Just _, Just today ) ->
            let
                ( subModel, subCmd ) =
                    Collection.init id today
            in
            ( { base | page = PageCollection subModel }, Cmd.map CollectionMsg subCmd )

        ( CollectionDetail _, Just _, Nothing ) ->
            -- Today not loaded yet; stay on Loading.
            ( { base | page = PageLoading }, Cmd.none )

        ( NotFound, _, _ ) ->
            ( { base | page = PageNotFound }, Cmd.none )


view : Model -> Browser.Document Msg
view model =
    { title = "cloudelog"
    , body =
        [ viewHeader model
        , case model.flash of
            Just f ->
                div [ class "flash" ] [ text f ]

            Nothing ->
                text ""
        , case model.page of
            PageLoading ->
                p [] [ text "Loading…" ]

            PageAuth subModel ->
                Html.map AuthMsg (Auth.view subModel)

            PageLogList subModel ->
                Html.map LogListMsg (LogList.view subModel)

            PageLogView subModel ->
                Html.map LogViewMsg (LogView.view model.device subModel)

            PageCollection subModel ->
                Html.map CollectionMsg (Collection.view subModel)

            PageNotFound ->
                p [] [ text "Not found." ]
        ]
    }


viewHeader : Model -> Html Msg
viewHeader model =
    case model.user of
        Just user ->
            div [ class "app-header", style "display" "flex", style "justify-content" "space-between", style "align-items" "baseline" ]
                [ h2 [] [ a [ href "/" ] [ text "cloudelog" ] ]
                , div []
                    [ text user.email
                    , text " · "
                    , button [ onClick LogoutRequested ] [ text "Sign out" ]
                    ]
                ]

        Nothing ->
            h2 [] [ text "cloudelog" ]
