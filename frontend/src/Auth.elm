module Auth exposing (Model, Msg(..), Mode(..), OutMsg(..), init, initWithEmail, update, view)

import Api
import Html exposing (Html, a, button, div, form, h1, input, p, text)
import Html.Attributes exposing (attribute, autocomplete, autofocus, disabled, href, placeholder, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Http


type Mode
    = LoginMode
    | SignupMode


type alias Model =
    { mode : Mode
    , email : String
    , password : String
    , submitting : Bool
    , error : Maybe String
    }


init : Mode -> Model
init mode =
    { mode = mode
    , email = ""
    , password = ""
    , submitting = False
    , error = Nothing
    }


initWithEmail : Mode -> String -> Model
initWithEmail mode email =
    { mode = mode
    , email = email
    , password = ""
    , submitting = False
    , error = Nothing
    }


type Msg
    = EmailChanged String
    | PasswordChanged String
    | Submitted
    | AuthResponded (Result Http.Error ())


type OutMsg
    = NoOp
    | AuthSucceeded


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        EmailChanged e ->
            ( { model | email = e }, Cmd.none, NoOp )

        PasswordChanged p ->
            ( { model | password = p }, Cmd.none, NoOp )

        Submitted ->
            if model.submitting then
                ( model, Cmd.none, NoOp )

            else
                let
                    cmd =
                        case model.mode of
                            LoginMode ->
                                Api.login model.email model.password AuthResponded

                            SignupMode ->
                                Api.signup model.email model.password AuthResponded
                in
                ( { model | submitting = True, error = Nothing }, cmd, NoOp )

        AuthResponded (Ok ()) ->
            ( { model | submitting = False }, Cmd.none, AuthSucceeded )

        AuthResponded (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }
            , Cmd.none
            , NoOp
            )


view : Model -> Html Msg
view m =
    div []
        [ h1 []
            [ text
                (case m.mode of
                    LoginMode ->
                        "Sign in to cloudelog"

                    SignupMode ->
                        "Create a cloudelog account"
                )
            ]
        , case m.error of
            Just e ->
                div [] [ text ("Error: " ++ e) ]

            Nothing ->
                text ""
        , form [ onSubmit Submitted, autocomplete False ]
            [ div []
                [ input
                    [ type_ "email"
                    , autofocus True
                    , placeholder "you@example.com"
                    , value m.email
                    , onInput EmailChanged
                    , attribute "autocomplete" "off"
                    ]
                    []
                ]
            , div []
                [ input
                    [ type_ "password"
                    , placeholder "Password (min 8 chars)"
                    , value m.password
                    , onInput PasswordChanged
                    , attribute "autocomplete" "new-password"
                    ]
                    []
                ]
            , button [ type_ "submit", disabled m.submitting ]
                [ text
                    (case ( m.mode, m.submitting ) of
                        ( LoginMode, True ) ->
                            "Signing in..."

                        ( LoginMode, False ) ->
                            "Sign in"

                        ( SignupMode, True ) ->
                            "Creating..."

                        ( SignupMode, False ) ->
                            "Create account"
                    )
                ]
            ]
        , p []
            (case m.mode of
                LoginMode ->
                    [ text "No account? "
                    , a [ href "/signup" ] [ text "Sign up" ]
                    ]

                SignupMode ->
                    [ text "Have an account? "
                    , a [ href "/login" ] [ text "Sign in" ]
                    ]
            )
        ]
