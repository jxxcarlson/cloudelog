# Edit entries from the collection page

Date: 2026-05-02
Status: design approved, pending implementation plan

## Summary

Make every History row on the collection detail page (`/collections/:id`)
editable in place. Clicking **Edit** on a row expands it into an inline
form with one quantity + description input per metric of that entry's
log. **Save** calls the existing `PUT /api/entries/:id`; on success the
page refetches `GET /api/collections/:id` and rerenders. **Cancel**
discards the draft. **Delete remains on the per-log page** — it is
explicitly out of scope here.

This lifts the v1 non-goal "Editing or deleting past entries from the
combined history view" from
`docs/superpowers/specs/2026-04-21-log-collections-design.md` (Non-goals,
line 427), but only for the *edit* half.

## Motivation

A user recording across a collection (e.g. "Piano practice") often
notices a typo or wants to amend a description while reviewing the day's
entries on the collection page. Today they have to navigate to the
member log's detail page, find the entry, edit it, and come back. That
breaks the collection page's role as the daily-use surface.

## Design decisions

1. **Edit only — no delete from the collection page.** Delete is the
   higher-stakes affordance and stays on the per-log page where the user
   sees the full single-log timeline before deleting. (User choice "A"
   during brainstorming.)
2. **Inline expansion in the History row, not a modal.** Same affordance
   as `LogView.elm`'s entry edit, so the UX is identical across the two
   pages. No modal infrastructure exists in the app today; introducing
   one for a single feature is overkill.
3. **At most one row in edit mode at a time.** Same invariant as
   `LogView.elm` (`editing : Maybe EditDraft`). Clicking Edit on a
   second row swaps; the prior draft is discarded silently.
4. **On save, refetch the whole collection.** Combined totals and
   per-log streak stats both depend on entry quantities and are derived
   server-side (per-log) and client-side (combined) from the full
   collection payload. The `EntryResponse` returned by `PUT
   /api/entries/:id` carries only the updated entry — not the recomputed
   streak — so a patch-in-place would leave streak stats stale until the
   next page load. Refetching is one extra request and keeps the page
   a pure projection of server state.
5. **No new backend.** `PUT /api/entries/:id` already validates
   ownership and recomputes streaks for the affected log inside the
   transaction. The collection page is just a new caller.

## Data model

No schema or API changes. The existing endpoints suffice:

- `PUT /api/entries/:id` — body `{ values: [{ quantity, description }] }`
  (`UpdateEntryRequest` in `backend/src/Api/RequestTypes.hs:106`).
  Returns the updated `EntryResponse`. Already recomputes the owning
  log's streaks.
- `GET /api/collections/:id` — returns `CollectionDetailResponse` with
  fresh per-member streak stats. Used for the post-save refetch.

## Frontend

All changes confined to `frontend/src/Collection.elm`. No other module
is touched.

### New types (local to `Collection.elm`)

```elm
type alias ValueDraft =
    { qty : String
    , desc : String
    }

type alias EditDraft =
    { entryId : String
    , values : List ValueDraft
    , submitting : Bool
    }
```

These mirror `LogView.elm`'s shapes (`LogView.elm:144`). They are
duplicated — not extracted to a shared module — because (a) the two
pages are the only two callers, (b) extraction would require a new
shared module just for two type aliases, and (c) the duplication makes
each page self-contained.

### Model additions

Extend `Collection.elm`'s page model with:

```elm
, editing : Maybe EditDraft
```

Initialized to `Nothing` in `init`. Reset to `Nothing` whenever a new
`CollectionDetailResponse` is installed into the model (the existing
`DetailFetched` and `CombinedPosted` handlers in `Collection.elm`), so
the form collapses after a successful save and after any external
refresh.

### Messages

```elm
| StartEdit Entry
| EditQtyChanged Int String
| EditDescChanged Int String
| SaveEdit
| CancelEdit
| EditSaved (Result Http.Error Entry)
```

### Update behavior

- `StartEdit e` → populate `editing` from `e.id` and `e.values` (each
  `Value` becomes a `ValueDraft` with `qty = String.fromFloat
  v.quantity` and `desc = v.description`); discard any prior draft.
- `EditQtyChanged i s` / `EditDescChanged i s` → update the i-th
  `ValueDraft` in `editing.values`. No-op if `editing` is `Nothing`.
- `CancelEdit` → set `editing = Nothing`. No network call.
- `SaveEdit` →
  - Parse each `qty` string with `String.toFloat`. If any fails, set
    `model.error = Just "Invalid number"` and don't submit. (Same
    behavior as `LogView.elm`'s save.)
  - Treat empty qty string as `0` (matches the per-log edit).
  - Mark `editing.submitting = True`, clear `error`, and call
    `Api.updateEntry d.entryId { values = parsedValues } EditSaved`.
- `EditSaved (Ok _)` → ignore the returned entry; issue
  `Api.getCollection model.collectionId DetailFetched` (reusing the
  existing init-time message). The `DetailFetched` handler will be
  amended to clear `editing` and `error` when it installs the fresh
  payload, so the form collapses on a successful save.
- `EditSaved (Err err)` → keep `editing` open with `submitting = False`
  and set `model.error` to a short human message. Same wording as the
  per-log edit's error path.

### View

`viewHistoryRow` (`Collection.elm:684`) currently renders a flex row of
`logName` + rendered values. Change it so:

- When `model.editing` is `Just d` and `d.entryId == row.entry.id`,
  render `viewHistoryEditRow row d` instead.
- Otherwise, render the existing read-only layout plus an **Edit**
  button at the right end (desktop) or below the row (phone).

`viewHistoryEditRow` renders, for each metric of the row's log:

- Desktop: a single horizontal row — `logName` (left), then per-metric
  `[qty input] [unit label] [description input]` segments, then a
  **Save** + **Cancel** pair on the right.
- Phone: stacked. Reuse the `row-phone-edit` CSS class already present
  for `LogView.elm`'s phone edit form. The first child is the log name
  + unit caption; then one stacked card per metric; then a full-width
  Save / Cancel pair.

Save is disabled while `d.submitting`. Cancel is always enabled.

The Edit button uses the same minimal styling as the existing per-log
Edit button so the two pages match.

### Wiring

`Collection.elm` already calls `Api.getCollection cid DetailFetched`
from `init`. The post-save refetch reuses the same helper and the same
`DetailFetched` message — no new request helper or decoder is needed.
(Note: the existing `CombinedPosted` handler patches the model from its
response payload directly rather than refetching; the edit flow
deliberately takes the refetch route instead — see decision 4.)

### What does *not* change

- `Api.elm`, `Types.elm`, `Main.elm`, `Route.elm`, `LogList.elm`,
  `LogView.elm` — untouched.
- The History row's read-only rendering when no row is being edited.
- Combined totals computation. Same data shape, recomputed on each
  rerender from the refetched payload.

## Backend

No changes. Confirmed available:

- `PUT /api/entries/:id` — `Handler/Entries.hs:97`, validates that the
  entry belongs to a log owned by the caller (returns 404 otherwise),
  upserts via `DbEntry.updateEntry`, and recomputes the log's streaks
  in the same transaction.
- `GET /api/collections/:id` — already returns fresh per-member
  `streakStats` and entries.

## Validation

- **Numeric qty.** Same as the per-log edit: empty → `0`; non-numeric →
  inline error, no submit.
- **No "all-or-nothing per-log" rule.** That rule belongs to the
  *combined add* form (where blank rows mean "skip that log"). Editing
  a single existing entry doesn't need it — the entry already exists
  and the user is just adjusting its values.
- **Future-date guard.** Not relevant; the entry's date is not editable
  through this flow (matches the per-log edit, which also doesn't let
  the user move an entry to a different date).

## Concurrency

Two pages editing the same entry behave the same as today on the per-log
page: last write wins. Not addressing.

## Skipped entries

A skip is just an entry with `quantity = 0` and empty description. The
edit flow has no special case for it: the user can type a non-zero
quantity to "un-skip", or zero out a real entry to skip it. The History
row's `(skipped)` rendering keys off the same condition it does today
(`Collection.elm:687`) and will recompute correctly after the refetch.

## Testing

- **No new pure functions.** The combined-totals algorithm is unchanged
  and `frontend/tests/CombinedTotalsTests.elm` still covers it.
- **Manual verification (CLAUDE.md).** The implementer must test in a
  browser before claiming completion:
  - Edit a non-skip entry, change its quantity → row collapses, History
    rerenders with the new value, "Per log" totals and "Combined
    totals" reflect the change, member's `Current streak` updates if
    the change crosses the active threshold.
  - Edit a skip entry to a real value → row no longer renders as
    `(skipped)`; combined totals pick it up.
  - Edit a real entry to qty=0 with empty description → row renders as
    `(skipped)`; combined totals drop it.
  - Click Edit on row A, then Edit on row B without saving → A's draft
    discarded silently, B opens.
  - Type non-numeric qty → inline error, row stays open, no network
    call.
  - Save against a network error → row stays open, error shown,
    Submitting flag clears, retrying works.
  - Phone breakpoint (≤600 px): edit form stacks per-metric, Save and
    Cancel are full-width.

## Non-goals

- Deleting entries from the collection page (per-log page owns delete).
- Editing the entry's date.
- A dedicated "convert to skip" / "un-skip" control (the user achieves
  both by editing values).
- Multi-row simultaneous edit.
- Optimistic updates / patch-in-place (intentionally chose refetch).
