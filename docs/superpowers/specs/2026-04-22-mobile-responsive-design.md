# Mobile-responsive cloudelog (v1)

## Goal

Make the daily-use flow of cloudelog readable and usable on an iPhone (portrait, 375–430 px wide). "Daily use" = open the app, pick a log, add today's entry, glance at stats, optionally edit an entry. Other flows — Collections, Auth, log-create/edit — work but are not tuned in this pass.

## Scope

**In scope (MVP):**

- Header / app shell (`Main.viewHeader`).
- Logs list (`LogList.elm`).
- Log detail view (`LogView.elm`), including: title + description + metrics row, stats pills, streaks cell, add-entry form, entries list, per-entry edit.

**Out of scope for this pass (render acceptably via shared CSS, no custom layout):**

- Collection page (`Collection.elm`).
- Auth page (`Auth.elm`).
- Log create / edit modal.

Nothing is broken for these — they inherit the page-wide CSS fixes (viewport meta, reduced body padding, 16 px form fonts, 44 px touch targets, flex-wrap-friendly defaults) and remain functional. Polishing them is a follow-up.

## Architecture

### The `Device` type

A single sum type, defined in `Types.elm` so every module can import it:

```elm
type Device
    = Phone
    | Desktop

classify : Int -> Device
classify widthPx =
    if widthPx < 600 then Phone else Desktop
```

**Breakpoint:** 600 px. Covers every iPhone portrait width (SE 375, 13/14/15 390, Pro Max 430) with headroom; iPads stay on Desktop in portrait.

### State and subscription

`Main.Model` gains one field:

```elm
{ ...
, device : Device
}
```

`Main.init` calls `Browser.Dom.getViewport` once at startup and stashes `classify (round viewport.scene.width)`. Until the task resolves, `device` defaults to `Desktop`; the flip to `Phone` happens on the next frame. If this flash proves visible in testing, the fallback is to read `window.innerWidth` in `index.html`'s init JS and pass it via Elm flags, eliminating the round trip.

`Main.subscriptions` adds `Browser.Events.onResize (\w _ -> ViewportResized w)`. `update` on `ViewportResized w` stores `classify w` in `model.device`. No other page's `Model` or `update` is involved.

### How pages see `Device`

Each page's `view` function gains a `Device ->` parameter. `Main.view` passes `model.device` down. Example:

```elm
-- LogView.elm (before)
view : Model -> Html Msg

-- LogView.elm (after)
view : Device -> Model -> Html Msg
```

Pages do not store `Device` in their own models. It is a render-time input, not persistent state.

### `index.html` fix

Add to `<head>`:

```html
<meta name="viewport" content="width=device-width, initial-scale=1">
```

Without this, iPhone Safari renders at 980 px and pinch-zoom-fits, making every other change cosmetic.

## Layout rules

### Shared CSS (`index.html` `<style>`)

One `@media (max-width: 600px)` block:

- `body` padding drops from `2rem` to `1rem`.
- `input, select, textarea` get `font-size: 16px` (prevents iOS Safari auto-zoom-on-focus).
- Interactive elements (`button`, edit/delete icons) get `min-height: 44px` and generous padding (Apple HIG touch target).
- `.stats { flex-wrap: wrap }` so per-metric stat pills wrap instead of clipping.
- Header flex-wraps so title, email, and logout never overflow.

These rules apply regardless of whether the current view also has Elm-side branching — they handle page-wide concerns.

### Elm-branched views

Three locations in `LogView.elm` render different DOM on `Phone` vs `Desktop`:

**1. Add-entry form.**

- Desktop: current single-line flex (per-metric qty input + desc input, then a Submit button).
- Phone: each metric rendered as a grouped labeled block (metric-name label → qty input full-width → desc input full-width). Full-width Submit button below.

**2. Entries row — display mode.**

- Desktop: current `.row` (date | per-metric values | edit/delete ctrls).
- Phone: stacked — date as header line, per-metric `name: qty — desc` lines below, edit/delete ctrls on a right-aligned trailing line.

**3. Entries row — edit mode.**

- Desktop: current inline edit form (the row's contents replaced by a form with N qty+desc pairs + Save/Cancel).
- Phone: stacked card — same shape as the phone add-entry form (labeled grouped-per-metric blocks), plus Save/Cancel full-width.

All other parts of `LogView` (title, description, metrics chips, streaks cell, stats pills, collection selector, description-edit popover) use only the shared CSS rules.

### LogList and header

CSS-only. Each `LogList` row stacks log-name above per-log-stats at `< 600px` via `@media`. The header wraps its children. No Elm branching in these modules.

## Testing

**Unit test.** One new test for `classify`:

- `classify 599 == Phone`
- `classify 600 == Desktop`
- `classify 0 == Phone`
- `classify 1920 == Desktop`

Pins the breakpoint and will fail loudly if someone nudges it by accident.

**Manual checklist, same PR.** Chrome DevTools responsive mode at 375 px (iPhone SE), 390 px (13/14/15), 430 px (Pro Max). For each width, verify:

- Header doesn't clip.
- `LogList` rows read cleanly.
- `LogView` title / stats / streak cell wrap without clipping.
- Add-entry form shows grouped-per-metric blocks on phone; submitting adds an entry and clears the form.
- Clicking edit on an entry shows the stacked card; Save updates the entry; Cancel restores it.
- Delete still works.

**Real device pass.** After deploy, open `https://cloudelog.app` on an actual iPhone Safari and repeat the checklist. DevTools emulation does not catch iOS-specific issues (auto-zoom on focus, tap-highlight colors, safe-area notches).

**Desktop regression spot-check.** At ≥ 1024 px, verify the layout is pixel-identical to before. All Elm branching is gated on `Device == Phone`; all CSS is inside `@media (max-width: 600px)`.

No new test infrastructure, no snapshot tests, no browser automation.

## Out-of-scope items (follow-up)

- Collection page mobile pass.
- Auth page mobile pass.
- Log create / edit modal mobile pass.
- Safe-area-inset handling for notched devices.
- Pull-to-refresh, swipe-to-delete, bottom tab bar — any "native-feel" iOS interaction patterns.

These should each be their own small spec once the MVP is in hand and we know what's actually annoying in real use.
