# cloudelog deployment runbook

Deploy target: the existing DigitalOcean droplet `root@161.35.125.40`, which already runs greppit (and scripta). cloudelog shares Postgres, nginx, stack, and elm with those apps; it just gets its own database, backend port, systemd unit, and nginx server block.

Domain: **cloudelog.app**, proxied through Cloudflare, TLS from Let's Encrypt (same pattern as greppit).

Backend port on the droplet: **8087** (greppit is 8086, scripta's backend is elsewhere — 8087 is free).

This runbook assumes you run as `root` on the droplet, matching greppit. That keeps ops consistent across the two apps; moving cloudelog to a dedicated non-root user later is a fine follow-up (tracked at the bottom).

---

## Phase 0 — Cookie security flag (already shipped)

The backend picks between Dev (insecure cookie) and Prod (Secure cookie) based on the `COOKIE_SECURE` env var. Shipped in commit `186007d`.

- `COOKIE_SECURE` unset / `false` → `cookieIsSecure = NotSecure` (localhost HTTP dev).
- `COOKIE_SECURE=true` → `cookieIsSecure = Secure` (HTTPS production).

The active mode is logged at startup (`cookieSecure=True/False`) so you can confirm it in `journalctl -u cloudelog-backend`.

> **Why it matters:** without `Secure` on HTTPS, browsers refuse to send the JWT cookie back over the wire and login silently fails — same class of bug as the cross-origin cookie issue we hit in dev. Setting `COOKIE_SECURE=true` in the production `.env` (Phase 3) enables it.

---

## Phase 1 — Droplet prerequisites

**Skip this phase.** The greppit deploy already installed everything (build-essential, libpq-dev, postgres, nginx, stack, elm, dbmate, certbot). Verify if paranoid:

```
which dbmate stack elm certbot pg_dump
```

If all five resolve, go to Phase 2.

## Phase 2 — Postgres

Create a dedicated user and database, parallel to greppit's:

```
sudo -u postgres createuser cloudelog
sudo -u postgres createdb -O cloudelog cloudelog_prod
sudo -u postgres psql -c "ALTER USER cloudelog WITH PASSWORD 'PICK-A-STRONG-ONE';"
```

## Phase 3 — Repo + `.env`

On the droplet (`ssh root@161.35.125.40`):

```
cd ~ && git clone https://github.com/jxxcarlson/cloudelog.git
cd cloudelog
cp .env.example .env
```

Edit `~/cloudelog/.env`. Minimum:

```
DATABASE_URL=postgres://cloudelog:STRONG-PASS@localhost/cloudelog_prod
PORT=8087
JWT_SECRET=<output of: openssl rand -base64 48>
JWT_EXPIRY_DAYS=7
COOKIE_SECURE=true
```

`COOKIE_SECURE=true` activates the Secure flag; the code that reads it is already in `main` (see Phase 0).

## Phase 4 — Migrations + first smoke test

```
cd ~/cloudelog
./run migrate up
cd backend && stack build
PORT=8087 ./run restart backend    # or bind via .env
```

Verify:

```
curl -s http://localhost:8087/api/health         # "ok"
bash backend/test-api.sh                         # every section passes
```

If green, tear down the dev-mode backend before installing the systemd unit:

```
./run kill
```

## Phase 5 — Production build of frontend

```
cd ~/cloudelog/frontend
elm make src/Main.elm --optimize --output=elm.js
```

nginx will serve `index.html`, `elm.js`, `favicon.svg` as static files. **`serve.py` is not used in production** — nginx both serves statics and reverse-proxies `/api/*`.

## Phase 6 — Install the backend binary and systemd unit

```
cd /root/cloudelog/backend
stack install --local-bin-path /usr/local/bin
ls -l /usr/local/bin/cloudelog-backend
```

Repeat this `stack install` whenever you rebuild the backend after a pull.

Install and start the service:

```
cp /root/cloudelog/deploy/cloudelog-backend.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cloudelog-backend
systemctl status cloudelog-backend           # active (running)
journalctl -u cloudelog-backend -f           # tail logs (Ctrl-C to stop)
```

From here on, restart the backend with `systemctl restart cloudelog-backend`, **not** `./run restart backend`.

## Phase 7 — nginx (HTTP only; cert arrives in Phase 8)

`deploy/nginx/cloudelog.conf` is HTTP-only by design — certbot patches the TLS listener + redirect in on first run, same pattern as greppit's config.

```
cp /root/cloudelog/deploy/nginx/cloudelog.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/cloudelog.conf /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

`nginx -t` should pass cleanly — no cert references yet, and the config uses a distinct `server_name` (`cloudelog.app`), so it won't conflict with greppit's block.

## Phase 8 — TLS cert (Let's Encrypt via certbot)

### DNS first

In the Cloudflare dashboard, add an A record:

- `cloudelog.app → 161.35.125.40`
- **Proxy status: DNS only** (grey cloud) *temporarily*, so Let's Encrypt's HTTP-01 challenge reaches the droplet directly.

Give DNS a minute, then verify:

```
dig +short cloudelog.app     # should return 161.35.125.40
```

### Issue the cert

```
certbot --nginx -d cloudelog.app
```

Certbot will:

1. Verify domain control via HTTP-01 (needs grey cloud at this moment).
2. Write the cert to `/etc/letsencrypt/live/cloudelog.app/`.
3. Patch `/etc/nginx/sites-available/cloudelog.conf` in place to add `listen 443 ssl`, the cert paths, and an HTTP → HTTPS redirect. You'll see `# managed by Certbot` comments appear.
4. Reload nginx.

Verify the patched config:

```
grep -n 'managed by Certbot' /etc/nginx/sites-available/cloudelog.conf
nginx -t
curl -sI http://cloudelog.app/       # 301 to https
curl -sI https://cloudelog.app/      # 200 (might need grey cloud still)
```

**Auto-renewal:** the existing `certbot.timer` on this droplet picks up the new cert automatically. `systemctl list-timers certbot.timer` to confirm.

## Phase 9 — Cloudflare proxy + SSL mode

Flip Cloudflare's proxy on now that the origin cert exists:

- DNS → set the `cloudelog.app` record to **Proxied** (orange cloud).
- SSL/TLS → Overview → **Full (strict)**. Let's Encrypt is trusted by Cloudflare, so Full (strict) works immediately. Never use "Flexible" — it's plaintext between Cloudflare and the droplet.
- SSL/TLS → Edge Certificates → **Always Use HTTPS: On**, **Min TLS 1.2**.

(Greppit's TLS/SSL settings already apply at the zone level if you configured them once; double-check they're enabled here.)

## Phase 10 — Verify

From a machine other than the droplet:

```
curl -sI https://cloudelog.app/                  # HTTP/2 200
curl -s  https://cloudelog.app/api/health        # "ok"
```

Open `https://cloudelog.app/` in a browser and sign up. Reload on a deep-link URL like `https://cloudelog.app/logs/<uuid>` to confirm the SPA fallback works. Sign out, sign back in — the session cookie should persist across reload now that `COOKIE_SECURE=true` is in effect.

---

## Ongoing operations

- **Schema change:** push the migration to git, pull on the server, `./run migrate up`, then `systemctl restart cloudelog-backend`.
- **Frontend update:** pull on the server, `cd frontend && elm make src/Main.elm --optimize --output=elm.js`. No service restart needed — nginx serves the new file on the next request.
- **Backend update:** pull on the server, `cd backend && stack install --local-bin-path /usr/local/bin`, then `systemctl restart cloudelog-backend`. (A plain `stack build` is not enough — the systemd unit runs the installed binary, not the stack snapshot.)
- **Backups on the droplet:** `scripts/db-dump-do.sh` writes to `~/cloudelog/backups/`. Cron suggestion:

  ```
  0 3 * * * /root/cloudelog/scripts/db-dump-do.sh >> /root/cloudelog/backups/cron.log 2>&1
  ```

  (Greppit already has a similar cron entry — cloudelog's can coexist on a different minute if you want to stagger them.)

- **Pull dumps to your Mac:** set these in your *local* `.env`, then run `scripts/db-fetch-dump.sh`:

  ```
  CLOUDELOG_PROD_HOST=root@161.35.125.40
  CLOUDELOG_PROD_BACKUP_DIR=/root/cloudelog/backups
  ```

- **Restore a dump locally:** `scripts/db-restore-local.sh` loads the latest dump in `backups/` into `cloudelog_dev`.

## Things that must never change after launch

- `JWT_SECRET` — changing it invalidates every issued token.
- The `users.id`, `logs.id`, and `entries.id` columns (all UUIDs that JWTs and foreign keys depend on).

## Things to revisit later

- Run cloudelog as a dedicated non-root user (`adduser cloudelog`, then `User=cloudelog` in the systemd unit and `chown -R cloudelog:cloudelog` on the checkout). Worth doing the next time either app needs a touch-up on the droplet — do greppit and cloudelog together for consistency.
- Rate-limit `/api/auth/*` in nginx to slow brute-force login attempts.
- `fail2ban` for ssh + nginx (shared across all apps on the droplet).
- `www.cloudelog.app` A record + add `-d www.cloudelog.app` to the certbot command if you want the www variant.
