# Cloudelog.app — Design

A web app for keeping daily quantity logs (time, distance, pages read, reps, etc.). Each log has one unit and one entry per calendar day. Missing days are auto-filled as "skipped" (quantity = 0) when the user adds a later entry.

Reference project for tech-stack conventions: `/Users/carlson/dev/greppit`.

## Decisions (from brainstorming)

| # | Decision |
|---|----------|
| Q1 | Unit lives on the log, not the entry. Every entry in a log uses that unit. |
| Q2 | Auth via HttpOnly cookie carrying a JWT (matches greppit's `Servant.Auth.Server` setup). No tokens in `localStorage`. |
| Q3 | "Total days since log started" = calendar days from first entry through today, inclusive. "Skipped days" = entries whose quantity is 0. Average = total ÷ (total days − skipped days). |
| Q4a | Skip-fill happens only when a new entry is written; fills calendar days strictly between the previous most-recent entry and the new one. |
| Q4b | `quantity == 0` *is* the skip marker — no separate flag. |
| Q5 | One entry per (log, calendar day). Enforced by a DB unique constraint. |
| Q6 | Adding a new entry on a day that already has one **accumulates** quantity. Descriptions overwrite only if the new one is non-empty. This makes "skip → real entry" a natural upgrade (0 + x = x). |
| Q7 | v1 scope: signup, signin, signout, log CRUD, entry CRUD with skip-fill + accumulate, stats. **Out of scope:** password reset, email verification, team sharing, property-based tests, browser automation, CI config. |
| Q8 | Unit input is a dropdown `Minutes | Hours | Kilometers | Miles | Custom…`. "Custom…" reveals a text box; the typed string is stored verbatim. |
| Q9 | Log fields editable: name, description, and unit — **but unit only while the log has zero entries**. |
| Arch | Server-authoritative skip-fill + client-computed stats. Server does the transactional fill on write; Elm aggregates entries into the four header numbers locally. |

## Architecture

Monorepo mirroring greppit:

```
cloudelog/
├── backend/          # Haskell + Servant + Hasql
│   ├── app/Main.hs
│   ├── src/
│   │   ├── App.hs, AppEnv.hs, AppError.hs, Config.hs
│   │   ├── Api/       Auth.hs, Logs.hs, Types.hs, RequestTypes.hs
│   │   ├── Db/        Pool.hs, User.hs, Log.hs, Entry.hs
│   │   ├── Handler/   Auth.hs, Logs.hs, Entries.hs
│   │   ├── Service/   Auth.hs, SkipFill.hs
│   │   └── Types/     Common.hs, User.hs, Log.hs, Entry.hs
│   ├── dbmate/migrations/
│   ├── test/
│   ├── test-api.sh
│   ├── greppit-backend.cabal-equivalent (package.yaml / stack.yaml)
│   └── run.sh
├── db/schema.sql
├── frontend/         # Elm SPA
│   ├── index.html
│   ├── elm.json
│   ├── serve.py
│   └── src/
│       ├── Main.elm       -- top-level Model/Update/View + routing
│       ├── Types.elm      -- User, Log, Entry, Unit
│       ├── Api.elm        -- HTTP + JSON codecs
│       ├── Auth.elm       -- login / signup page
│       ├── LogList.elm    -- list-of-logs page
│       └── LogView.elm    -- single-log page (header + entry list)
├── scripts/          # be_restart.sh, fe_restart.sh, kill.sh, migrate.sh, psql.sh, ...
└── docs/superpowers/specs/
```

Routing (Elm `Browser.application`):

| Route | Module | Auth-gated |
|-------|--------|------------|
| `/login` | Auth | no |
| `/signup` | Auth | no |
| `/` | LogList | yes (redirects to `/login` otherwise) |
| `/logs/:id` | LogView | yes |

At startup, Main issues `GET /api/auth/me`; a `200` populates `model.user` and the app renders; a `401` redirects to `/login`.

## Data model

Three tables. Primary keys are `text` (UUIDv4 generated in Haskell) to match greppit.

```sql
CREATE TABLE users (
  id             text PRIMARY KEY,
  email          text UNIQUE NOT NULL,
  pw_hash        text NOT NULL,
  current_log_id text,                        -- nullable; FK added after logs table
  created_at     timestamptz DEFAULT now() NOT NULL,
  updated_at     timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE logs (
  id          text PRIMARY KEY,
  user_id     text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text DEFAULT '' NOT NULL,
  unit        text NOT NULL,                  -- 'minutes'|'hours'|'kilometers'|'miles'|<custom>
  created_at  timestamptz DEFAULT now() NOT NULL,
  updated_at  timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX logs_user_updated_idx ON logs (user_id, updated_at DESC);

ALTER TABLE users
  ADD CONSTRAINT users_current_log_fk
  FOREIGN KEY (current_log_id) REFERENCES logs(id) ON DELETE SET NULL;

CREATE TABLE entries (
  id          text PRIMARY KEY,
  log_id      text NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  entry_date  date NOT NULL,                  -- calendar day, not timestamp
  quantity    double precision NOT NULL DEFAULT 0,
  description text DEFAULT '' NOT NULL,
  created_at  timestamptz DEFAULT now() NOT NULL,
  updated_at  timestamptz DEFAULT now() NOT NULL,
  UNIQUE (log_id, entry_date)
);
CREATE INDEX entries_log_date_idx ON entries (log_id, entry_date);
```

Notes:

- `unit` is plain text. The four standard values are stored lowercase (`minutes`, `hours`, `kilometers`, `miles`); custom units are stored verbatim. A custom unit equalling one of the standard names is treated as a standard unit on read (edge case — accepted).
- `entry_date` is a `date`, not `timestamptz`. The client computes "today" in its local timezone and sends that date. This sidesteps TZ ambiguity for a calendar-day log.
- `(log_id, entry_date)` uniqueness enforces one entry per day (Q5) and is the `ON CONFLICT` target for accumulate upserts.
- `quantity = 0` is the skip marker (Q4b).

## API

JSON over HTTP. All `/api/*` routes require the auth cookie except `/api/auth/signup` and `/api/auth/login`.

```
POST   /api/auth/signup      {email, password}                     → 204 + Set-Cookie
POST   /api/auth/login       {email, password}                     → 204 + Set-Cookie
POST   /api/auth/logout                                            → 204 + clears cookie
GET    /api/auth/me                                                → {id, email}

GET    /api/logs                                                   → [LogSummary]
POST   /api/logs             {name, unit, description?}            → Log
GET    /api/logs/:id                                               → {log, entries}
PUT    /api/logs/:id         {name, description, unit?}            → Log
DELETE /api/logs/:id                                               → 204

POST   /api/logs/:id/entries {entry_date, quantity, description?}  → {entries}
PUT    /api/entries/:id      {quantity, description}               → Entry
DELETE /api/entries/:id                                            → 204
```

- `LogSummary` = `{id, name, unit, description, createdAt, updatedAt}` (no entries).
- `GET /api/logs/:id` response: `{log: Log, entries: [Entry]}`, entries ordered by `entry_date` ascending. Elm reverses for display.
- `PUT /api/logs/:id` accepts `unit` only when the log has zero entries; otherwise returns `400 Bad Request` with message `"Cannot change unit of a log that has entries"`.
- `PUT /api/entries/:id`: `entry_date` is not part of the payload — the date of an entry is immutable.
- `POST /api/logs/:id/entries`: returns the **full entry list** after the fill + upsert, so the client can re-render stats without a round-trip.

### Skip-fill algorithm (`POST /api/logs/:id/entries`)

Single DB transaction:

```
begin;
  -- 1. Verify log exists and belongs to the authenticated user.
  --    SELECT ... FOR UPDATE serializes concurrent entry writes for this log.
  select user_id from logs where id = :log_id for update;

  -- 2. Find the last entry date.
  select max(entry_date) into :last_date from entries where log_id = :log_id;

  -- 3. If the new entry is strictly after the last, fill the gap with skips.
  if :last_date is not null and :entry_date > :last_date then
    insert into entries (id, log_id, entry_date, quantity, description)
    select :new_skip_id_n, :log_id, d::date, 0, ''
    from generate_series(:last_date + 1, :entry_date - 1, interval '1 day') as d
    on conflict (log_id, entry_date) do nothing;
  end if;

  -- 4. Insert or accumulate the user's entry.
  insert into entries (id, log_id, entry_date, quantity, description)
  values (:new_id, :log_id, :entry_date, :quantity, :description)
  on conflict (log_id, entry_date) do update
    set quantity    = entries.quantity + excluded.quantity,
        description = case when excluded.description <> ''
                           then excluded.description
                           else entries.description end,
        updated_at  = now();

  -- 5. Return full list for client re-render.
  select * from entries where log_id = :log_id order by entry_date asc;
commit;
```

UUIDs are generated in Haskell; the schematic SQL above uses placeholder names. For step 3, Haskell computes the list of dates first and issues either a multi-row `INSERT ... VALUES (...)` or parameterised `generate_series` with pre-generated IDs — an implementation detail for the writing-plans phase.

**Edge cases:**

- First-ever entry: `:last_date IS NULL` → skip step 3; just insert.
- Back-fill (`:entry_date ≤ :last_date`): skip step 3; upsert accumulates onto an existing row (a prior skip or a prior real entry).
- Same-day re-add: step 4 accumulates.
- Concurrent adds on the same log: `FOR UPDATE` serializes; unique constraint is a backstop.

## Auth

- Servant with `Servant.Auth.Server`. Cookie auth enabled; Bearer JWT disabled for simplicity (v1 only has a browser client).
- Passwords hashed with `bcrypt` at cost 12.
- On signup or login, server issues an HttpOnly, `Secure`, `SameSite=Lax` cookie containing a JWT signed with `JWT_SECRET` from env. Expiry: 30 days (configurable via `JWT_EXPIRY_DAYS`, same as greppit).
- Email validated with a minimal regex at the API edge (`.+@.+\..+`); password min length 8.
- `POST /api/auth/logout` sets the cookie with an expired `Max-Age=0`.

## Frontend

Elm `Browser.application`. Top-level model:

```elm
type alias Model =
  { key : Nav.Key
  , route : Route
  , user : Maybe User
  , today : Date
  , page : PageModel
  , flash : Maybe String
  }

type PageModel
  = Loading
  | AuthModel Auth.Model
  | LogListModel LogList.Model
  | LogViewModel LogView.Model
```

At startup, Main requests `today` from JS (ports or `Task.perform` with `Time.now` + `Time.here`) and `/api/auth/me`. Based on results it routes to `/login` or the landing page.

Each page module (`Auth`, `LogList`, `LogView`) exposes `Model`, `Msg`, `init : ... -> (Model, Cmd Msg)`, `update : Msg -> Model -> (Model, Cmd Msg)`, `view : Model -> Html Msg`. Main forwards messages via `Cmd.map` / `Html.map`.

**Shared types (`Types.elm`)**:

```elm
type alias User  = { id : String, email : String }
type alias Log   =
  { id : String, name : String, unit : Unit
  , description : String, createdAt : Posix, updatedAt : Posix }
type alias Entry =
  { id : String, logId : String, date : Date
  , quantity : Float, description : String }

type Unit = Minutes | Hours | Kilometers | Miles | Custom String
```

Unit serialization: lowercase string; exact match to the four standards, anything else decodes to `Custom s`.

**Api.elm**: one function per endpoint, `Cmd Msg`-shaped with a `Result Http.Error a -> Msg` continuation. Cookies are sent automatically by the browser, so the API layer only needs URLs + JSON codecs + credentials flag.

### LogView page

```
┌────────────────────────────────────────────────────────────┐
│  Running log                         [Edit]  [Delete]      │
│  Unit: minutes                                             │
│                                                            │
│  Days:  42      Skipped: 11     Total: 1,320    Avg: 42.6  │
│                                                            │
│  Something something running.                              │
│                                                            │
│  Add entry:  [ 30       ] [ describe… ]  [Add]             │
│                                                            │
│  2026-04-18   30     great pace              [Edit] [Del]  │
│  2026-04-17   0      skipped                 [Edit] [Del]  │
│  2026-04-16   25     easy run                [Edit] [Del]  │
│  ...                                                       │
└────────────────────────────────────────────────────────────┘
```

Stats computed in `LogView.computeStats : List Entry -> Date -> Stats`:

```elm
type alias Stats = { days : Int, skipped : Int, total : Float, average : Maybe Float }

computeStats : List Entry -> Date -> Stats
computeStats entries today =
  case List.sortBy (Date.toRataDie << .date) entries of
    [] ->
      { days = 0, skipped = 0, total = 0, average = Nothing }

    firstEntry :: _ ->
      let
        days    = Date.diff Date.Days firstEntry.date today + 1
        skipped = List.length (List.filter (\e -> e.quantity == 0) entries)
        total   = List.sum (List.map .quantity entries)
        active  = days - skipped
        average = if active > 0 then Just (total / toFloat active) else Nothing
      in
      { days = days, skipped = skipped, total = total, average = average }
```

Empty-list and zero-active-days renderings display `—` in place of the number.

### LogList page

Shows a list of logs (ordered by `updated_at DESC`). "New log" button opens an inline form with `name`, `unit` (dropdown with Custom…), and optional `description`. Each row has Edit and Delete controls. Clicking a row navigates to `/logs/:id`.

Selecting a log also sets `current_log_id` on the user — see "Open items" for the exact mechanism. Delete shows a confirm dialog ("Delete log 'Running'? This cannot be undone.").

### Auth pages

Plain forms. Submit → API call → on success navigate to `/`.

## Error handling

**Backend.** `AppError` ADT with variants `NotFound | Forbidden | BadRequest Text | Conflict Text | Unauthorized | Internal Text`. Mapped in one place to Servant `ServerError` with status codes and a JSON body `{error: "<variant>", message: "<text>"}`. Validation at the API edge: email format, password min length 8, unit non-empty and ≤32 chars, quantity finite.

**Frontend.** `Http.Error` rendered into the top-level `flash` banner. A `401` anywhere clears `model.user` and redirects to `/login`. Network failures show "Network error — try again."

## Testing

- *Backend unit (hspec):* `Service.SkipFill.datesToFill :: Maybe Date -> Date -> [Date]` — pure function, easy to exhaust cases (no last date, same-day, gap, back-fill).
- *Backend integration:* `test-api.sh` driving curl through the signup → create-log → post-entries flow with assertions on JSON output. Runs against a disposable local DB (`createdb cloudelog_test` / `dbmate up` / `pg_terminate_backend`).
- *Frontend (elm-test):* `LogView.computeStats` and the `Unit` encoder/decoder.

Explicitly out of scope: property-based tests, browser automation, load tests, CI config. These belong in a later iteration.

## Deployment

Not in v1 scope beyond what greppit already provides as a template. `scripts/` will include the equivalents of greppit's local dev scripts (`be_restart.sh`, `fe_restart.sh`, `kill.sh`, `migrate.sh`, `psql.sh`). Production deploy is explicitly deferred.

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `DATABASE_URL` | — | Postgres connection string |
| `PORT` | `8081` | Backend HTTP port (avoids 8000–8010 per user preference) |
| `JWT_SECRET` | — | HMAC signing key for auth cookie |
| `JWT_EXPIRY_DAYS` | `30` | Cookie/JWT lifetime |

## Open items (deferred to writing-plans)

- Exact Hasql statement style: `hasql-th` quasi-quotes vs. hand-written `Statement` values. Greppit's choice will decide.
- Whether `current_log_id` is updated server-side on `GET /api/logs/:id` (on visit) or via an explicit `PUT /api/users/me/current-log`. Leaning toward implicit update on visit; confirm in plan.
