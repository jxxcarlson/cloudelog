# Edit Entries in Collections — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user edit any history entry in place from the collection detail page (`/collections/:id`), reusing the existing `PUT /api/entries/:id` endpoint and refetching the collection on save.

**Architecture:** Frontend-only change. All edits happen inside `frontend/src/Collection.elm` plus a one-line `frontend/src/Main.elm` tweak to thread `Device` into `Collection.view`. The model gains an `editing : Maybe EditDraft` field; six new messages drive a Start → Type → Save / Cancel cycle that mirrors `LogView.elm`. On successful save, the page issues `Api.getCollection` again and the existing `DetailFetched` handler clears the draft when the fresh payload arrives.

**Tech Stack:** Elm 0.19.1 (frontend). Backend untouched (Haskell + Servant + hasql).

**Spec:** `docs/superpowers/specs/2026-05-02-edit-entries-in-collections-design.md`

---

## File Map

- **Modify** `frontend/src/Collection.elm` — add types, model field, messages, update branches, edit-form view, Edit button on history rows. This is the only substantive change.
- **Modify** `frontend/src/Main.elm:352` — change `Collection.view subModel` to `Collection.view model.device subModel`.

No new files. No backend changes. No new tests (per spec § Testing — combined-totals is unchanged; verification is manual in-browser per `CLAUDE.md`).

---

## Task 1: Thread `Device` into `Collection.view`

**Files:**
- Modify: `frontend/src/Collection.elm` (signature of `view`, top of `view` body)
- Modify: `frontend/src/Main.elm:352`

This is a no-behavior-change refactor that makes `Device` available inside `Collection.view`. Subsequent tasks need it to render the edit form's phone vs. desktop layout.

- [ ] **Step 1: Add `Device` to `Collection.elm`'s imports**

In `frontend/src/Collection.elm`, find this line near the top:

```elm
import Types exposing (Collection, CollectionDetail, CollectionMember, CombinedTotal, Entry, Log, Metric)
```

Replace with:

```elm
import Types exposing (Collection, CollectionDetail, CollectionMember, CombinedTotal, Device(..), Entry, Log, Metric)
```

- [ ] **Step 2: Change `view`'s signature**

In `frontend/src/Collection.elm`, find:

```elm
view : Model -> Html Msg
view model =
```

Replace with:

```elm
view : Device -> Model -> Html Msg
view device model =
```

The `device` parameter is unused for now; later tasks will thread it into the history rows.

- [ ] **Step 3: Update the caller in `Main.elm`**

In `frontend/src/Main.elm` find line 352:

```elm
            PageCollection subModel ->
                Html.map CollectionMsg (Collection.view subModel)
```

Replace with:

```elm
            PageCollection subModel ->
                Html.map CollectionMsg (Collection.view model.device subModel)
```

- [ ] **Step 4: Verify compile**

Run from `frontend/`:

```bash
cd frontend && elm make src/Main.elm --output=/dev/null
```

Expected: `Success!` (no errors). If unused-parameter warnings appear, ignore them — `device` will be used in Task 5.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Collection.elm frontend/src/Main.elm
git commit -m "frontend: thread Device into Collection.view (no behavior change)"
```

---

## Task 2: Add edit-draft types and model field

**Files:**
- Modify: `frontend/src/Collection.elm` (model types, `init`, `emptyDraftsFor` block region)

Introduce the `EditDraft` type and the `editing : Maybe EditDraft` model field. Note: `Collection.elm` already declares a `ValueDraft` (line 12-13) used by the combined-add form. We'll **reuse** that exact `ValueDraft` for the edit draft — no new alias needed.

- [ ] **Step 1: Add `EditDraft` type alias**

In `frontend/src/Collection.elm`, find the existing `LogDraft` declaration (around line 16-17):

```elm
type alias LogDraft =
    { logId : String, values : List ValueDraft }
```

Immediately *after* it, add:

```elm
type alias EditDraft =
    { entryId : String
    , values : List ValueDraft
    , submitting : Bool
    }
```

- [ ] **Step 2: Add `editing` field to `Model`**

In `frontend/src/Collection.elm`, find the `Model` record (around line 20):

```elm
type alias Model =
    { collectionId : String
    , today : Date
    , detail : Maybe CollectionDetail
    , loading : Bool
    , error : Maybe String
    , drafts : List LogDraft
    , submitting : Bool
    }
```

Replace with:

```elm
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
```

- [ ] **Step 3: Initialize `editing = Nothing` in `init`**

In `frontend/src/Collection.elm` find `init` (around line 45-56):

```elm
init : String -> Date -> ( Model, Cmd Msg )
init cid today =
    ( { collectionId = cid
      , today = today
      , detail = Nothing
      , loading = True
      , error = Nothing
      , drafts = []
      , submitting = False
      }
    , Api.getCollection cid DetailFetched
    )
```

Replace with:

```elm
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
```

- [ ] **Step 4: Verify compile**

```bash
cd frontend && elm make src/Main.elm --output=/dev/null
```

Expected: `Success!`. The new field is unused so far — that's fine, Elm doesn't warn about unused record fields.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Collection.elm
git commit -m "frontend: add EditDraft type and editing field to Collection model"
```

---

## Task 3: Add edit messages (no handlers yet — only the type)

**Files:**
- Modify: `frontend/src/Collection.elm` (Msg union)

Adding the constructors first lets the next task add update branches one by one without the compiler complaining about a partially-handled `Msg` union — Elm forces all `case` branches at once, so we add the constructors and the branches together in Task 4. To keep that diff small, just expand the type here.

- [ ] **Step 1: Extend the `Msg` union**

In `frontend/src/Collection.elm` find (around line 31-37):

```elm
type Msg
    = DetailFetched (Result Http.Error CollectionDetail)
    | OpenLog String
    | DraftQtyChanged String Int String
    | DraftDescChanged String Int String
    | SubmitCombined
    | CombinedPosted (Result Http.Error CollectionDetail)
```

Replace with:

```elm
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
```

- [ ] **Step 2: Verify compile fails with the expected missing-branches error**

```bash
cd frontend && elm make src/Main.elm --output=/dev/null
```

Expected: FAIL with a "MISSING PATTERNS" / "This `case` does not have branches for all possibilities" error pointing at the `update` function in `Collection.elm`. This is normal — Task 4 adds the branches. Do not commit yet.

---

## Task 4: Add update branches for the new messages

**Files:**
- Modify: `frontend/src/Collection.elm` (`update` function, `DetailFetched` and `CombinedPosted` branches; six new branches)

This task adds all six new branches in one compile-clean step, plus amends the two existing handlers (`DetailFetched`, `CombinedPosted`) to clear `editing` and any stale draft when fresh detail arrives.

- [ ] **Step 1: Amend `DetailFetched (Ok d)` to clear `editing`**

In `frontend/src/Collection.elm` find the `DetailFetched (Ok d)` branch (around line 107-116):

```elm
        DetailFetched (Ok d) ->
            ( { model
                | detail = Just d
                , loading = False
                , error = Nothing
                , drafts = emptyDraftsFor d.members
              }
            , Cmd.none
            , NoOp
            )
```

Replace with:

```elm
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
```

- [ ] **Step 2: Amend `CombinedPosted (Ok d)` to clear `editing`**

Find `CombinedPosted (Ok d)` (around line 192-201):

```elm
        CombinedPosted (Ok d) ->
            ( { model
                | detail = Just d
                , drafts = emptyDraftsFor d.members
                , submitting = False
                , error = Nothing
              }
            , Cmd.none
            , NoOp
            )
```

Replace with:

```elm
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
```

- [ ] **Step 3: Add the six new branches at the end of the `update` `case`**

In `frontend/src/Collection.elm`, find the `CombinedPosted (Err err)` branch (around line 203-207):

```elm
        CombinedPosted (Err err) ->
            ( { model | submitting = False, error = Just (Api.apiErrorToString err) }
            , Cmd.none
            , NoOp
            )
```

Immediately *after* it (still inside the `case msg of` block — i.e. before the blank line that ends the function), add:

```elm
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
            ( { model | editing = Nothing, error = Nothing }, Cmd.none, NoOp )

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
```

Notes on this code:
- `updateAt` already exists in `Collection.elm` (line 73-83) — reuse it.
- The `SaveEdit` parser treats an empty qty string as `0` (matches the spec's validation rule and the per-log edit's behavior). A non-empty, non-numeric qty blocks save with the inline message.
- `EditSaved (Ok _)` discards the returned entry and triggers a refetch via `Api.getCollection ... DetailFetched`. The `DetailFetched` handler (Step 1) clears `editing`.
- `EditSaved (Err err)` keeps the form open with `submitting = False` so the user can retry.

- [ ] **Step 4: Verify compile**

```bash
cd frontend && elm make src/Main.elm --output=/dev/null
```

Expected: `Success!`. There may be an "unused" warning for the new `Msg` constructors if no view emits them yet — that's fine until Task 5 wires the buttons.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Collection.elm
git commit -m "frontend: add update branches for editing collection entries"
```

---

## Task 5: Render Edit button and inline edit form in the History rows

**Files:**
- Modify: `frontend/src/Collection.elm` (`viewHistory`, `viewHistoryDay`, `viewHistoryRow`; thread `device` and `editing` from `view`)

This task wires the new messages to UI: a small **Edit** button per history row, and an inline edit form that replaces the row's read-only rendering when `model.editing.entryId` matches.

- [ ] **Step 1: Pass `device` and `editing` through `view` → `viewHistory`**

In `frontend/src/Collection.elm` find the call inside `view` (around line 245):

```elm
                , viewHistory d.members
```

Replace with:

```elm
                , viewHistory device model.editing d.members
```

- [ ] **Step 2: Update `viewHistory` signature and forward to `viewHistoryDay`**

In `frontend/src/Collection.elm` find `viewHistory` (around line 628):

```elm
viewHistory : List CollectionMember -> Html Msg
viewHistory members =
```

Replace the signature line with:

```elm
viewHistory : Device -> Maybe EditDraft -> List CollectionMember -> Html Msg
viewHistory device editing members =
```

Then in the same function, find:

```elm
        div []
            [ h3 [] [ text "History" ]
            , div [] (List.map viewHistoryDay groups)
            ]
```

Replace with:

```elm
        div []
            [ h3 [] [ text "History" ]
            , div [] (List.map (viewHistoryDay device editing) groups)
            ]
```

- [ ] **Step 3: Update `viewHistoryDay` signature and forward to `viewHistoryRow`**

In `frontend/src/Collection.elm` find `viewHistoryDay` (around line 676):

```elm
viewHistoryDay : ( Date, List HistoryRow ) -> Html Msg
viewHistoryDay ( date, rows ) =
    div [ style "margin" "0.75rem 0" ]
        (h4 [] [ text (Date.toIsoString date) ]
            :: List.map viewHistoryRow rows
        )
```

Replace with:

```elm
viewHistoryDay : Device -> Maybe EditDraft -> ( Date, List HistoryRow ) -> Html Msg
viewHistoryDay device editing ( date, rows ) =
    div [ style "margin" "0.75rem 0" ]
        (h4 [] [ text (Date.toIsoString date) ]
            :: List.map (viewHistoryRow device editing) rows
        )
```

- [ ] **Step 4: Replace `viewHistoryRow` body to switch on edit state**

In `frontend/src/Collection.elm` find the entire `viewHistoryRow` definition (around line 684-729):

```elm
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
```

Replace with:

```elm
viewHistoryRow : Device -> Maybe EditDraft -> HistoryRow -> Html Msg
viewHistoryRow device editing { logName, metrics, entry } =
    case editing of
        Just d ->
            if d.entryId == entry.id then
                viewHistoryEditRow device logName metrics d

            else
                viewHistoryDisplayRow device logName metrics entry

        Nothing ->
            viewHistoryDisplayRow device logName metrics entry


viewHistoryDisplayRow : Device -> String -> List Metric -> Entry -> Html Msg
viewHistoryDisplayRow device logName metrics entry =
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

        editBtn =
            button [ onClick (StartEdit entry) ] [ text "Edit" ]
    in
    case device of
        Types.Phone ->
            div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.25rem"
                , style "padding" "0.4rem 0"
                , style "border-bottom" "1px solid #eee"
                ]
                [ div [ style "color" "#555", style "font-weight" "500" ] [ text logName ]
                , div [] [ text rendered ]
                , div
                    [ style "display" "flex"
                    , style "justify-content" "flex-end"
                    , style "margin-top" "0.25rem"
                    ]
                    [ editBtn ]
                ]

        Types.Desktop ->
            div
                [ style "display" "flex"
                , style "gap" "1rem"
                , style "align-items" "baseline"
                , style "padding" "0.2rem 0"
                ]
                [ div [ style "min-width" "10rem", style "color" "#555" ] [ text logName ]
                , div [ style "flex" "1 1 auto" ] [ text rendered ]
                , div [] [ editBtn ]
                ]


viewHistoryEditRow : Device -> String -> List Metric -> EditDraft -> Html Msg
viewHistoryEditRow device logName metrics d =
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
        Types.Phone ->
            div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.5rem"
                , style "padding" "0.6rem 0"
                , style "border-bottom" "1px solid #eee"
                ]
                ([ div [ style "color" "#555", style "font-weight" "500" ] [ text logName ] ]
                    ++ List.indexedMap (viewHistoryEditValue Types.Phone metrics) d.values
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

        Types.Desktop ->
            div
                [ style "display" "flex"
                , style "gap" "1rem"
                , style "align-items" "baseline"
                , style "padding" "0.4rem 0"
                , style "flex-wrap" "wrap"
                ]
                [ div [ style "min-width" "10rem", style "color" "#555" ] [ text logName ]
                , div
                    [ style "display" "flex"
                    , style "flex-direction" "column"
                    , style "gap" "0.25rem"
                    , style "flex" "1 1 auto"
                    , style "min-width" "0"
                    ]
                    (List.indexedMap (viewHistoryEditValue Types.Desktop metrics) d.values)
                , div [ style "display" "flex", style "gap" "0.5rem" ]
                    [ saveButton, cancelButton ]
                ]


viewHistoryEditValue : Device -> List Metric -> Int -> ValueDraft -> Html Msg
viewHistoryEditValue device metrics i v =
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

        qtyInput =
            input
                [ type_ "number"
                , attribute "inputmode" "decimal"
                , value v.qty
                , onInput (EditQtyChanged i)
                , style "width" "5rem"
                ]
                []

        descInput =
            input
                [ type_ "text"
                , value v.desc
                , onInput (EditDescChanged i)
                , style "flex" "1 1 auto"
                , style "min-width" "0"
                ]
                []

        unitLabel =
            if String.isEmpty unitText then
                text ""

            else
                span [ style "color" "#666" ] [ text unitText ]
    in
    case device of
        Types.Phone ->
            div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "gap" "0.25rem"
                ]
                ((if String.isEmpty labelText then
                    []

                  else
                    [ div [ style "color" "#666", style "font-size" "0.85rem" ] [ text labelText ] ]
                 )
                    ++ [ div
                            [ style "display" "flex"
                            , style "gap" "0.5rem"
                            , style "align-items" "baseline"
                            ]
                            [ qtyInput, unitLabel ]
                       , descInput
                       ]
                )

        Types.Desktop ->
            div
                [ style "display" "flex"
                , style "gap" "0.5rem"
                , style "align-items" "baseline"
                , style "flex-wrap" "wrap"
                ]
                ((if String.isEmpty labelText then
                    []

                  else
                    [ div [ style "min-width" "6rem", style "color" "#666" ] [ text labelText ] ]
                 )
                    ++ [ qtyInput, unitLabel, descInput ]
                )
```

Notes on this code:
- `viewHistoryEditRow` takes only the draft — not the `Entry` — because the draft already carries the qty/desc strings being edited.
- The example uses qualified `Types.Phone` / `Types.Desktop`, which always work because `Types` is imported. Since Task 1 also added `Device(..)` to the exposed list, unqualified `Phone` / `Desktop` would compile too. Either is fine; pick one and stay consistent inside this file.
- The `attribute "inputmode" "decimal"` matches `LogView.elm`'s edit form (better mobile keyboard).

- [ ] **Step 5: Add `attribute` and `disabled` and `span` and `input`-related imports if missing**

The new view code uses `Html.Attributes.attribute`, `Html.Attributes.disabled`, `Html.Attributes.value`, `Html.Attributes.type_`, `Html.span`, `Html.input`. The existing `import Html exposing (..)` and `import Html.Attributes exposing (..)` at the top of `Collection.elm` already pull all of these in via the `(..)` open-import — no import changes needed.

Verify by inspecting the imports near the top of `Collection.elm`. They should look like:

```elm
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
```

If `Html.Events` doesn't already export `onClick` and `onInput`, both are listed in the existing import — no change.

- [ ] **Step 6: Verify compile**

```bash
cd frontend && elm make src/Main.elm --output=/dev/null
```

Expected: `Success!`. If you see "I cannot find a `Phone` constructor" or similar, switch to qualified `Types.Phone` / `Types.Desktop` consistently in the new code (or vice versa).

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Collection.elm
git commit -m "frontend: edit history entries inline on the collection page"
```

---

## Task 6: Manual verification in the browser

**Files:** none (verification only).

The spec explicitly defers test coverage to manual verification. Run the dev server and exercise each scenario from § Testing of the spec.

- [ ] **Step 1: Start the dev server**

From the repo root:

```bash
./run/fe-dev
```

(or whatever script the project uses for the frontend dev server — check `frontend/package.json` or the `run/` directory). The CLAUDE.md note says to avoid ports 8000-8010; use whatever port the existing dev script picks.

- [ ] **Step 2: Load a collection with at least two member logs and some history**

Sign in (use the seeded user or create one), navigate to `/logs`, click into a collection. If no collection exists, create one via the **+ New collection** button on `/logs`, then assign two existing logs to it (the spec's per-log "Edit" form has a collection picker).

Make sure the History section has both a real entry and a `(skipped)` entry. If not, use the combined-add form to add one of each across different days.

- [ ] **Step 3: Run each scenario**

Follow the spec's manual-verification list:

- Edit a non-skip entry, change its quantity → row collapses on Save, History rerenders with the new value, "Per log" totals and "Combined totals" reflect the change, member's `Current streak` updates if the change crosses the active threshold.
- Edit a skip entry to a real value → row no longer renders as `(skipped)`; combined totals pick it up.
- Edit a real entry to qty=0 with empty description → row renders as `(skipped)`; combined totals drop it.
- Click Edit on row A, then Edit on row B without saving → A's draft is discarded silently, B opens.
- Type non-numeric qty (e.g. "abc") → inline error appears, row stays open, no network call (verify in DevTools Network tab).
- Save against a network error (DevTools → Network → Offline; click Save) → row stays open, error shown, retry succeeds after Network → Online.
- Phone breakpoint (resize the window to ≤600 px width or use DevTools' device emulator): edit form stacks per-metric, Save and Cancel are full-width.

For each scenario, note the result. If any fails, debug before moving on — do not claim completion.

- [ ] **Step 4: Confirm no regression on per-log page**

Open `/logs/:id` for a member log of the collection. Verify the existing inline edit on the per-log page still works (this plan didn't touch `LogView.elm`, but the shared backend endpoint and refetched stats should behave identically).

- [ ] **Step 5: Commit nothing; report verification results**

This task produces no commit. Either everything passes (the prior task's commit stands as the feature's artifact) or you fix issues with follow-up commits.

---

## Self-Review Notes

Coverage check against `docs/superpowers/specs/2026-05-02-edit-entries-in-collections-design.md`:

| Spec section | Covered by |
|---|---|
| Edit only, no delete | Tasks 3-5 add only edit messages and an Edit button; no delete UI |
| Inline expansion | Task 5 swaps row rendering when `editing.entryId` matches |
| One row at a time | Update branch in Task 4: `StartEdit` always overwrites `editing`, never appends |
| Refetch on save | Task 4 `EditSaved (Ok _)` issues `Api.getCollection ... DetailFetched` |
| `editing` cleared on fresh detail | Task 4 amends both `DetailFetched` and `CombinedPosted` |
| Validation: empty qty → 0; non-numeric → blocked | Task 4 `SaveEdit` parser |
| Phone vs. desktop layout | Task 1 threads `Device`; Task 5 branches on it |
| No backend changes | Confirmed — no backend files touched |
| Manual verification | Task 6 covers each spec bullet |

No placeholders, no "TODO", no "similar to". Each step contains the concrete code or command needed.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-02-edit-entries-in-collections.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
