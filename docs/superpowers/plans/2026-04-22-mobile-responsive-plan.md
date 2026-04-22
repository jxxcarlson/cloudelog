# Mobile-Responsive Cloudelog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily-use flow of cloudelog (logs list + log detail + header) readable and usable on iPhone portrait widths (375–430 px), without breaking desktop.

**Architecture:** Introduce a `Device = Phone | Desktop` type (breakpoint 600 px) tracked only in `Main.Model`, populated once at init and refreshed on resize. `Main.view` passes it only to `LogView.view` — the single place where DOM shape needs to change. Everything else (header flex-wrap, LogList row stacking, touch targets, input font-size, stats wrap) is CSS-only, inside a single `@media (max-width: 600px)` block in `index.html`. No new routes, no new page models, no new dependencies.

**Tech Stack:** Elm 0.19.1, `elm/browser` 1.0.2 (already in deps: gives `Browser.Dom.getViewport`, `Browser.Events.onResize`), `elm-explorations/test` for unit tests. HTML/CSS changes live in `frontend/index.html`.

**Spec:** `docs/superpowers/specs/2026-04-22-mobile-responsive-design.md`.

---

## File Structure

**Create:**
- `frontend/tests/DeviceTests.elm` — one test module pinning the breakpoint.

**Modify:**
- `frontend/src/Types.elm` — add `Device` type + `classify` function; expose them.
- `frontend/index.html` — add viewport meta tag; add `@media (max-width: 600px)` block.
- `frontend/src/Main.elm` — add `device` to `Model`, init task for `getViewport`, resize subscription, new `Msg` variants; add `class "app-header"` to the header div; thread `device` into `LogView.view` call.
- `frontend/src/LogView.elm` — add `Device` import; change `view` signature to take `Device`; add `Device` args and `Phone`/`Desktop` branches to `viewNewEntryForm`, `viewValueDraftRow`, `viewEntryRow`, `viewReadRow`, `viewEditRow`, `viewEditValueRow`.

Other pages (`Auth.elm`, `LogList.elm`, `Collection.elm`) are untouched — they inherit the page-wide CSS and don't need Elm-side branching in this MVP.

---

## Task 1: Add `Device` type + `classify` + unit test

**Files:**
- Modify: `frontend/src/Types.elm`
- Create: `frontend/tests/DeviceTests.elm`

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/DeviceTests.elm`:

```elm
module DeviceTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types exposing (Device(..), classify)


suite : Test
suite =
    describe "Types.classify"
        [ test "just below breakpoint is Phone" <|
            \_ -> Expect.equal Phone (classify 599)
        , test "at breakpoint is Desktop" <|
            \_ -> Expect.equal Desktop (classify 600)
        , test "very small width is Phone" <|
            \_ -> Expect.equal Phone (classify 0)
        , test "typical desktop width is Desktop" <|
            \_ -> Expect.equal Desktop (classify 1920)
        ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx elm-test tests/DeviceTests.elm`
Expected: FAIL. The Elm compiler should complain about `Types` not exposing `Device` and `classify`.

- [ ] **Step 3: Add `Device` + `classify` to `Types.elm`**

Edit `frontend/src/Types.elm`. First update the module line to expose the new symbols — add `Device(..)` and `classify` to the exposing list:

```elm
module Types exposing
    ( User
    , Log
    , LogSummary
    , Entry
    , EntryValue
    , Metric
    , StreakStats
    , Collection
    , CollectionSummary
    , CollectionMember
    , CollectionDetail
    , CombinedTotal
    , Device(..)
    , classify
    )
```

Then append the new type and function at the end of the file:

```elm


type Device
    = Phone
    | Desktop


classify : Int -> Device
classify widthPx =
    if widthPx < 600 then
        Phone

    else
        Desktop
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx elm-test tests/DeviceTests.elm`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `cd frontend && npx elm-test`
Expected: PASS for all existing tests plus the new 4.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/tests/DeviceTests.elm
git commit -m "frontend: add Device type and classify with 600px breakpoint"
```

---

## Task 2: Add viewport meta tag to index.html

This single change is independently valuable: without it every later change is cosmetic (iPhone Safari renders at 980 px and pinch-zoom-fits otherwise). Ship it as its own commit.

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the meta tag**

In `frontend/index.html`, inside `<head>`, after the existing `<title>cloudelog</title>` line (currently line 4), add:

```html
    <meta name="viewport" content="width=device-width, initial-scale=1">
```

The full `<head>` after this change starts with:

```html
<head>
    <meta charset="utf-8" />
    <title>cloudelog</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    ...
```

- [ ] **Step 2: Manually verify in a browser**

Open the app in Chrome (or Safari). Open DevTools → toggle device toolbar → iPhone SE (375×667).

Expected: the page uses 375 logical px, not 980-scaled. Text at a legible size, no pinch-zoom required to read. Layout will still look cramped — that's Task 3.

- [ ] **Step 3: Commit**

```bash
git add frontend/index.html
git commit -m "frontend: add viewport meta tag for proper mobile rendering"
```

---

## Task 3: Add shared phone CSS and header class

Adds the single `@media (max-width: 600px)` block that handles page-wide concerns (body padding, iOS-safe input font-size, touch targets, stats wrap, header wrap). Also gives the header a `class "app-header"` so the CSS can target it (the header currently uses inline styles which CSS would need `!important` to override).

**Files:**
- Modify: `frontend/index.html`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Add the `app-header` class to the header div**

In `frontend/src/Main.elm`, the `viewHeader` function (currently around line 338). Update the `Just user` branch:

```elm
viewHeader : Model -> Html Msg
viewHeader model =
    case model.user of
        Just user ->
            div
                [ class "app-header"
                , style "display" "flex"
                , style "justify-content" "space-between"
                , style "align-items" "baseline"
                ]
                [ h2 [] [ a [ href "/" ] [ text "cloudelog" ] ]
                , div []
                    [ text user.email
                    , text " · "
                    , button [ onClick LogoutRequested ] [ text "Sign out" ]
                    ]
                ]

        Nothing ->
            h2 [] [ text "cloudelog" ]
```

(Only the first argument to `div` changes — it gains `class "app-header"` before the existing `style` attributes.)

- [ ] **Step 2: Add the `@media` block to `index.html`**

In `frontend/index.html`, inside the existing `<style>` block, immediately before `</style>`, append:

```css
      @media (max-width: 600px) {
        body { padding: 1rem; }
        input, select, textarea { font-size: 16px; }
        button { min-height: 44px; padding: 0.6rem 0.9rem; }
        .stats { flex-wrap: wrap; }
        .app-header { flex-wrap: wrap; gap: 0.5rem; }
        .row { flex-wrap: wrap; }
      }
```

Notes on the rules:
- `body { padding: 1rem }` — existing desktop value is `2rem`.
- `input, select, textarea { font-size: 16px }` — iOS Safari auto-zooms on focus for any input below 16 px; pinning at 16 px prevents the zoom.
- `button { min-height: 44px; padding: 0.6rem 0.9rem }` — Apple HIG recommends ≥ 44 pt touch targets. Existing desktop padding is `0.4rem 0.6rem`.
- `.stats { flex-wrap: wrap }` — per-metric stat pills wrap to multiple rows instead of clipping at narrow widths.
- `.app-header { flex-wrap: wrap; gap: 0.5rem }` — title on first line, email+logout wrap to second line.
- `.row { flex-wrap: wrap }` — LogList and LogView rows' children (`.date`, `.desc`, `.ctrls`) wrap. This is enough for LogList (its rows don't need Elm branching per the spec); LogView's row content is replaced via Elm branching in later tasks, so this wrap rule is a safety net for any `.row` that still renders the desktop shape.

- [ ] **Step 3: Compile and smoke-test**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: compiles cleanly, no errors.

Then reload the app in DevTools iPhone-SE mode (375 px). Expected:
- Body padding is visibly tighter.
- Header wraps: title on its own line, email+Sign-out below.
- On a logs list with many columns, `.row` children wrap instead of clipping.
- Existing desktop view at ≥ 1024 px looks unchanged.

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html frontend/src/Main.elm
git commit -m "frontend: shared @media phone CSS and app-header class"
```

---

## Task 4: Main tracks viewport and Device, passes Device to LogView

Wire up the runtime sensing: `Main` learns its viewport width once at init and on every resize, classifies it into `Device`, and passes the result into `LogView.view`.

`LogView.view`'s signature changes in this task but no Elm-side branching happens yet — `view` accepts the new parameter and ignores it. The branching lands in tasks 5–7. This keeps the build green after this task.

**Files:**
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/src/LogView.elm`

- [ ] **Step 1: Import the new modules and Types symbols in `Main.elm`**

In `frontend/src/Main.elm`, update imports. Replace the existing `import Types exposing (User)` with:

```elm
import Browser.Dom
import Browser.Events
import Types exposing (Device(..), User, classify)
```

(Add `Browser.Dom` and `Browser.Events`, widen the `Types` import.)

- [ ] **Step 2: Add `device` to `Model`**

In `frontend/src/Main.elm`, update the `Model` record alias:

```elm
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
```

- [ ] **Step 3: Add `Msg` variants**

In `frontend/src/Main.elm`, extend the `Msg` type to include two new variants. The new variants are:

```elm
    | GotInitialViewport Browser.Dom.Viewport
    | ViewportResized Int
```

Add them at the end of the existing `Msg` definition, so the full type becomes (the last two items are new):

```elm
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
```

- [ ] **Step 4: Initialise `device` to `Desktop` and fetch viewport at startup**

In `frontend/src/Main.elm`, update `init` to include `device = Desktop` in the initial record, and add a third command to `Cmd.batch` that fetches the viewport:

```elm
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
```

- [ ] **Step 5: Handle the new messages in `update`**

Add two branches to `Main.update`. Place them before the final branch of the case expression (exact location doesn't matter — the case is exhaustive):

```elm
        GotInitialViewport vp ->
            ( { model | device = classify (round vp.viewport.width) }
            , Cmd.none
            )

        ViewportResized w ->
            ( { model | device = classify w }
            , Cmd.none
            )
```

- [ ] **Step 6: Subscribe to resize events**

In `frontend/src/Main.elm`, replace the `main` block's `subscriptions = \_ -> Sub.none` with a named `subscriptions` function. Update `main`:

```elm
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
```

Then add the `subscriptions` function anywhere in the file (e.g. near `update`):

```elm
subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onResize (\w _ -> ViewportResized w)
```

- [ ] **Step 7: Change `LogView.view` signature to accept `Device`**

In `frontend/src/LogView.elm`, first add `Device` to the `Types` import:

```elm
import Types exposing (CollectionSummary, Device(..), Entry, EntryValue, Log, Metric, StreakStats)
```

Then change `view` from `Model -> Html Msg` to `Device -> Model -> Html Msg`:

```elm
view : Device -> Model -> Html Msg
view _ model =
    -- existing body unchanged; `_` ignored for now, used by later tasks
    ...
```

(Everything inside `view`'s body stays exactly as it is. The only change in this task is the type signature and binding the new first parameter to `_`.)

- [ ] **Step 8: Pass `model.device` into `LogView.view` from `Main.view`**

In `frontend/src/Main.elm`'s `view` function, change the `PageLogView` branch from:

```elm
            PageLogView subModel ->
                Html.map LogViewMsg (LogView.view subModel)
```

to:

```elm
            PageLogView subModel ->
                Html.map LogViewMsg (LogView.view model.device subModel)
```

- [ ] **Step 9: Compile**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: compiles cleanly.

- [ ] **Step 10: Run tests**

Run: `cd frontend && npx elm-test`
Expected: PASS (existing tests still pass; `DeviceTests` still passes).

- [ ] **Step 11: Manually verify viewport tracking**

Open the app in a browser. Resize the window from wide (≥ 1024 px) down past 600 px and back up. The app should not crash or flicker. No visible rendering change yet — that's tasks 5–7.

(Optional check: add a temporary `Debug.log "device" model.device` call in `Main.view` to confirm the state updates. Remove before committing.)

- [ ] **Step 12: Commit**

```bash
git add frontend/src/Main.elm frontend/src/LogView.elm
git commit -m "frontend: track viewport/Device in Main, thread into LogView.view"
```

---

## Task 5: LogView — phone branch for the add-entry form

Render the add-entry form as grouped labeled cards on `Phone`, keeping the existing inline-flex layout on `Desktop`. One branch, affecting `viewNewEntryForm` and `viewValueDraftRow`.

**Files:**
- Modify: `frontend/src/LogView.elm`

- [ ] **Step 1: Change `viewNewEntryForm` to take `Device`**

In `frontend/src/LogView.elm`, update `viewNewEntryForm`'s signature and thread `device` into the child call:

```elm
viewNewEntryForm : Device -> List Metric -> List ValueDraft -> Bool -> Html Msg
viewNewEntryForm device metrics drafts submitting =
    Html.form
        [ onSubmit AddEntry
        , style "width" "100%"
        , style "display" "block"
        ]
        (List.indexedMap (viewValueDraftRow device metrics) drafts
            ++ [ button
                    [ type_ "submit"
                    , class "primary"
                    , disabled submitting
                    , style "flex" "0 0 auto"
                    , style "margin-top" "0.25rem"
                    , case device of
                        Phone ->
                            style "width" "100%"

                        Desktop ->
                            style "width" "auto"
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
```

(The only differences from the current body are: signature gains `Device ->`; the child call passes `device`; the submit button gains a `Device`-branched `width` style for full-width on phone.)

- [ ] **Step 2: Replace `viewValueDraftRow` with a branched version**

Replace the existing `viewValueDraftRow` with the version below. Each branch inlines the two inputs with the styles it needs — no shared helper, because Elm's `Html msg` is opaque and you can't add attributes to an already-built node:

```elm
viewValueDraftRow : Device -> List Metric -> Int -> ValueDraft -> Html Msg
viewValueDraftRow device metrics i v =
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
    case device of
        Phone ->
            div
                [ class "entry-row-phone"
                , style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.25rem"
                , style "margin-bottom" "0.75rem"
                ]
                ((if String.isEmpty labelText then
                    []

                  else
                    [ div
                        [ style "color" "#555"
                        , style "font-size" "0.9rem"
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
                            , style "width" "100%"
                            , style "box-sizing" "border-box"
                            ]
                            []
                       , input
                            [ type_ "text"
                            , placeholder "note (optional)"
                            , value v.desc
                            , onInput (NewDescChanged i)
                            , style "width" "100%"
                            , style "box-sizing" "border-box"
                            ]
                            []
                       ]
                )

        Desktop ->
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
```

- [ ] **Step 3: Update the call site in `view`**

In `frontend/src/LogView.elm`, find the call to `viewNewEntryForm` (currently around line 536 inside `view`) and add `device` as a first argument. The caller in `view` receives `device` from the new signature (see Task 4, Step 7) — bind it instead of `_`:

```elm
view : Device -> Model -> Html Msg
view device model =
    ...
```

And the line that was:

```elm
                , viewNewEntryForm log.metrics model.newValues model.submitting
```

becomes:

```elm
                , viewNewEntryForm device log.metrics model.newValues model.submitting
```

- [ ] **Step 4: Compile**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: compiles cleanly.

- [ ] **Step 5: Manually verify**

Open the app, navigate to any log with ≥ 2 metrics, open DevTools, toggle 390 px width.
Expected: the add-entry form renders as stacked blocks — each metric shows its name label, then a full-width quantity input, then a full-width description input, then a full-width "Add entry" button.
Switch DevTools to ≥ 1024 px width and reload: the form looks identical to before.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/LogView.elm
git commit -m "frontend: stacked add-entry form on Phone (per-metric grouped cards)"
```

---

## Task 6: LogView — phone branch for entries row display

Render each entry row as a stacked card on `Phone`: date on top, per-metric lines below, edit/delete at the bottom. Desktop keeps the existing `.row` layout.

**Files:**
- Modify: `frontend/src/LogView.elm`

- [ ] **Step 1: Change `viewEntryRow` signature to take `Device` and thread it into children**

In `frontend/src/LogView.elm`, replace the current `viewEntryRow`:

```elm
viewEntryRow : Device -> List Metric -> Maybe EditDraft -> Entry -> Html Msg
viewEntryRow device metrics editing e =
    case editing of
        Just d ->
            if d.entryId == e.id then
                viewEditRow device metrics e d

            else
                viewReadRow device metrics e

        Nothing ->
            viewReadRow device metrics e
```

- [ ] **Step 2: Replace `viewReadRow` with a branched version**

Replace the current `viewReadRow` with:

```elm
viewReadRow : Device -> List Metric -> Entry -> Html Msg
viewReadRow device metrics e =
    let
        isSkipped =
            List.all (\v -> v.quantity == 0 && String.isEmpty v.description) e.values

        unitAt i =
            metrics
                |> List.drop i
                |> List.head
                |> Maybe.map (.unit >> abbrevUnit)
                |> Maybe.withDefault ""

        metricNameAt i =
            metrics
                |> List.drop i
                |> List.head
                |> Maybe.map .name
                |> Maybe.withDefault ""

        renderValueInline i v =
            let
                unit =
                    unitAt i
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

        renderValueLine i v =
            let
                name =
                    metricNameAt i

                prefix =
                    if String.isEmpty name || List.length metrics <= 1 then
                        ""

                    else
                        name ++ ": "

                unit =
                    unitAt i

                body =
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
            in
            div [ style "color" "#333" ] [ text (prefix ++ body) ]

        desktopBody =
            if isSkipped then
                "(skipped)"

            else
                String.join " · " (List.indexedMap renderValueInline e.values)
    in
    case device of
        Phone ->
            div
                [ class "row-phone"
                , style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.25rem"
                , style "padding" "0.6rem 0"
                , style "border-bottom" "1px solid #eee"
                ]
                ([ div [ style "color" "#666", style "font-weight" "500" ]
                    [ text (Date.toIsoString e.date) ]
                 ]
                    ++ (if isSkipped then
                            [ div [ style "color" "#888" ] [ text "(skipped)" ] ]

                        else
                            List.indexedMap renderValueLine e.values
                       )
                    ++ [ div
                            [ style "display" "flex"
                            , style "gap" "0.5rem"
                            , style "justify-content" "flex-end"
                            , style "margin-top" "0.25rem"
                            ]
                            [ button [ onClick (StartEdit e) ] [ text "Edit" ]
                            , button [ onClick (DeleteEntry e.id) ] [ text "Del" ]
                            ]
                       ]
                )

        Desktop ->
            div [ class "row" ]
                [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
                , div [ class "desc" ] [ text desktopBody ]
                , div [ class "ctrls" ]
                    [ button [ onClick (StartEdit e) ] [ text "Edit" ]
                    , button [ onClick (DeleteEntry e.id) ] [ text "Del" ]
                    ]
                ]
```

- [ ] **Step 3: Update `viewEditRow` signature to accept `Device` without branching yet**

`viewEditRow`'s body will change in Task 7, but in this task we only widen its signature so `viewEntryRow` can compile:

```elm
viewEditRow : Device -> List Metric -> Entry -> EditDraft -> Html Msg
viewEditRow _ metrics e d =
    -- existing body unchanged
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
```

(Only the signature and the `_` binding are new; inner body is unchanged.)

- [ ] **Step 4: Update the call site in `view` to pass `device` to `viewEntryRow`**

In `frontend/src/LogView.elm`, find where `viewEntryRow metrics model.editing` or similar is invoked (inside `view`'s body, mapping over entries). Add `device` as first arg. For example, if the current code is:

```elm
List.map (viewEntryRow log.metrics model.editing) model.entries
```

change it to:

```elm
List.map (viewEntryRow device log.metrics model.editing) model.entries
```

Use `grep` to find the exact call: `grep -n "viewEntryRow " frontend/src/LogView.elm`. There should be one call inside `view`.

- [ ] **Step 5: Compile**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: compiles cleanly.

- [ ] **Step 6: Manually verify**

DevTools at 390 px. Each entry row renders as: ISO date on its own line, then one `name: qty unit — note` line per metric (or `"(skipped)"` for skips), then the Edit/Del buttons right-aligned at the bottom. Each row separated by a thin bottom border.

DevTools at ≥ 1024 px: rows look identical to before.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/LogView.elm
git commit -m "frontend: stacked entry rows on Phone (display mode)"
```

---

## Task 7: LogView — phone branch for entries row edit

Complete the pair: on `Phone`, the edit form for an entry renders as a stacked card with grouped per-metric blocks and full-width Save/Cancel. On `Desktop`, keep the existing inline edit.

**Files:**
- Modify: `frontend/src/LogView.elm`

- [ ] **Step 1: Replace `viewEditRow` with a branched version**

Replace the current `viewEditRow` (updated in Task 6 Step 3) with:

```elm
viewEditRow : Device -> List Metric -> Entry -> EditDraft -> Html Msg
viewEditRow device metrics e d =
    let
        saveButton =
            button [ onClick SaveEdit, disabled d.submitting ]
                [ text
                    (if d.submitting then
                        "Saving…"

                     else
                        "Save"
                    )
                ]

        cancelButton =
            button [ onClick CancelEdit, disabled d.submitting ] [ text "Cancel" ]
    in
    case device of
        Phone ->
            div
                [ class "row-phone-edit"
                , style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.5rem"
                , style "padding" "0.6rem 0"
                , style "border-bottom" "1px solid #eee"
                ]
                ([ div [ style "color" "#666", style "font-weight" "500" ]
                    [ text (Date.toIsoString e.date) ]
                 ]
                    ++ List.indexedMap (viewEditValueRow Phone metrics) d.values
                    ++ [ div
                            [ style "display" "flex"
                            , style "gap" "0.5rem"
                            , style "margin-top" "0.25rem"
                            ]
                            [ div [ style "flex" "1 1 auto" ] [ saveButton ]
                            , div [ style "flex" "1 1 auto" ] [ cancelButton ]
                            ]
                       ]
                )

        Desktop ->
            div [ class "row", style "flex-wrap" "wrap" ]
                [ div [ class "date" ] [ text (Date.toIsoString e.date) ]
                , div
                    [ style "display" "flex"
                    , style "flex-direction" "column"
                    , style "gap" "0.25rem"
                    , style "flex" "1 1 auto"
                    , style "min-width" "0"
                    ]
                    (List.indexedMap (viewEditValueRow Desktop metrics) d.values)
                , div [ class "ctrls" ]
                    [ saveButton, cancelButton ]
                ]
```

Note: `viewEditValueRow` now takes `Device` as its first argument — done in the next step.

- [ ] **Step 2: Add a `Device` parameter to `viewEditValueRow` and branch**

Replace the current `viewEditValueRow` with:

```elm
viewEditValueRow : Device -> List Metric -> Int -> ValueDraft -> Html Msg
viewEditValueRow device metrics i v =
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
    case device of
        Phone ->
            div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.25rem"
                ]
                ((if String.isEmpty labelText then
                    []

                  else
                    [ div
                        [ style "color" "#555"
                        , style "font-size" "0.9rem"
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
                            , style "width" "100%"
                            , style "box-sizing" "border-box"
                            ]
                            []
                       , input
                            [ value v.desc
                            , onInput (EditDescChanged i)
                            , placeholder "note (optional)"
                            , style "width" "100%"
                            , style "box-sizing" "border-box"
                            ]
                            []
                       ]
                )

        Desktop ->
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
```

- [ ] **Step 3: Compile**

Run: `cd frontend && elm make src/Main.elm --output=elm.js`
Expected: compiles cleanly.

- [ ] **Step 4: Run tests**

Run: `cd frontend && npx elm-test`
Expected: PASS.

- [ ] **Step 5: Manually verify phone edit flow**

DevTools at 390 px. On any log with ≥ 1 entry:
- Click Edit on a row. The row should expand into a stacked card: date at the top, per-metric block (label + full-width qty + full-width desc), Save and Cancel each taking half width at the bottom.
- Change the quantity and click Save. The row should return to display mode with the updated quantity.
- Click Edit again, click Cancel. The row should return to display mode unchanged.

DevTools at ≥ 1024 px: editing a row looks identical to before (inline form inside `.row`).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/LogView.elm
git commit -m "frontend: stacked edit form on Phone (per-metric card, full-width Save/Cancel)"
```

---

## Task 8: Final verification checklist

No code changes — just the manual sweep the spec requires before calling the feature done.

**Files:** none.

- [ ] **Step 1: DevTools pass at all three anchor widths**

Open Chrome DevTools → device toolbar.

For each of `375 px` (iPhone SE), `390 px` (iPhone 13/14/15), `430 px` (Pro Max):

- Sign in (if not already). Header wraps cleanly, no overflow.
- LogList: rows render; each row's name and stats read cleanly without clipping.
- Open a log with ≥ 2 metrics. Title/description, streak cell, stats pills all wrap cleanly.
- Add-entry form shows grouped per-metric blocks; Submit is full-width.
- Type a quantity + description, tap Submit. The entry appears in the list as a stacked card (date top, per-metric lines, Edit/Del at bottom).
- Tap Edit. Stacked edit card appears. Change the qty. Tap Save. Row collapses back to display mode with the new value.
- Tap Edit again. Tap Cancel. Row returns to its prior display unchanged.
- Tap Del on a disposable entry. Row disappears.

- [ ] **Step 2: Real-device pass**

After deploy to `cloudelog.app`, open it on an actual iPhone Safari. Repeat the Step 1 checklist. Specifically look for:

- Inputs do **not** zoom on focus (16 px font-size did its job).
- Buttons are comfortable to tap (≥ 44 px hit area).
- Pinch-zoom is not required to read anything.
- No horizontal scroll on any page.

If iOS Safari shows problems DevTools didn't — most commonly the initial Desktop → Phone flip as a visible flash — apply the mitigation from the spec (read `window.innerWidth` in `index.html`'s init JS and pass as an Elm flag). That's a separate follow-up task, not part of this MVP plan.

- [ ] **Step 3: Desktop regression spot-check**

Resize the browser to ≥ 1024 px. Verify:
- Header, LogList, LogView all look pixel-identical to how they looked before this branch started.
- Add-entry form uses the old inline-flex layout.
- Entry rows use the old `.row` layout with date | values | ctrls columns.
- Edit form uses the old inline edit layout.

- [ ] **Step 4: If all green, merge to `main`**

```bash
# from the phone branch with everything committed:
git checkout main
git merge --no-ff phone
git push
```

(If working in a worktree, adjust accordingly.)

---

## Self-review notes

- Every task ends with a commit. Each commit leaves the app in a working, compilable state. Tasks 5, 6, and 7 are specifically ordered so `viewEntryRow` / `viewEditRow` signature widening in Task 6 happens *before* Task 7 fills in the edit-branch body — the pattern "change signature to `_`-ignored in Task N, use in Task N+1" keeps intermediate commits green.
- The spec's four-point test for `classify` is fully present in Task 1. The `@media (max-width: 600px)` block with all page-wide rules is Task 3. The three Elm-branched views (add-entry form, entries row display, entries row edit) are Tasks 5, 6, 7. The manual DevTools + real-device checklist is Task 8. All five spec sections (Goal, Scope, Architecture, Layout rules, Testing) are covered.
- `Auth.elm`, `LogList.elm`, `Collection.elm`, and `Route.elm` are not modified. The spec explicitly excludes them from this MVP pass; they inherit the shared `@media` rules and remain functional.
