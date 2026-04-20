#!/usr/bin/env bash
# End-to-end API smoke test. Assumes the backend is running and reachable.
# Default target is localhost:8081 (dev); override via BASE env var, e.g.
#   BASE=http://localhost:8087 bash backend/test-api.sh
# The DB is expected to be clean-ish (a unique email per run sidesteps collisions).
set -u

BASE="${BASE:-http://localhost:8081}"
EMAIL="test-$(date +%s)@example.com"
PW="hunter22"
COOKIES="/tmp/cloudelog-test-cookies-$$"
trap 'rm -f "$COOKIES"' EXIT

say() { printf "\n=== %s ===\n" "$1"; }
ok()  { printf "  ✓ %s\n" "$1"; }
fail(){ printf "  ✗ %s\n" "$1"; exit 1; }

say "Health"
curl -sS "$BASE/api/health" | grep -q '"ok"' && ok "health" || fail "health"

say "Signup"
curl -sS -c "$COOKIES" -X POST "$BASE/api/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" \
  -o /dev/null -w "http %{http_code}\n" | grep -q "204" && ok "signup 204" || fail "signup"

say "Me (cookie)"
ME=$(curl -sS -b "$COOKIES" "$BASE/api/auth/me")
echo "$ME" | grep -q "$EMAIL" && ok "me returns email" || fail "me"

TODAY=$(date -u +%Y-%m-%d)
# macOS date uses -v; GNU date uses -d. Pick whichever works.
if date -u -v-3d +%Y-%m-%d >/dev/null 2>&1; then
  THREE_DAYS_AGO=$(date -u -v-3d +%Y-%m-%d)
  TOMORROW=$(date -u -v+1d +%Y-%m-%d)
else
  THREE_DAYS_AGO=$(date -u -d '3 days ago' +%Y-%m-%d)
  TOMORROW=$(date -u -d '1 day' +%Y-%m-%d)
fi

say "Create log with explicit startDate 3 days ago (expect 3 skip-fill entries)"
LOG_SD=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Backfilled\",\"unit\":\"minutes\",\"description\":\"\",\"startDate\":\"$THREE_DAYS_AGO\"}")
LOG_SD_ID=$(echo "$LOG_SD" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
SD_IN_RESP=$(echo "$LOG_SD" | python3 -c 'import sys,json; print(json.load(sys.stdin)["startDate"])')
[ "$SD_IN_RESP" = "$THREE_DAYS_AGO" ] && ok "startDate echoed in response" || fail "startDate response ($SD_IN_RESP)"

GOT=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_SD_ID")
N_ENTRIES=$(echo "$GOT" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N_ENTRIES" = "3" ] && ok "3 backfilled entries present" || fail "expected 3 entries, got $N_ENTRIES"
ALL_ZERO=$(echo "$GOT" | python3 -c 'import sys,json; es=json.load(sys.stdin)["entries"]; print(all(e["quantity"]==0 and e["description"]=="" for e in es))')
[ "$ALL_ZERO" = "True" ] && ok "all backfilled entries are zero/empty" || fail "backfilled entries not zero/empty"

say "Create log with no startDate (expect startDate == today, 0 entries)"
LOG_TODAY=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"TodayOnly","unit":"minutes","description":""}')
LOG_TODAY_ID=$(echo "$LOG_TODAY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
SD_TODAY=$(echo "$LOG_TODAY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["startDate"])')
[ "$SD_TODAY" = "$TODAY" ] && ok "startDate defaults to today" || fail "default startDate ($SD_TODAY vs $TODAY)"
N_TODAY=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_TODAY_ID" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N_TODAY" = "0" ] && ok "no entries when startDate == today" || fail "expected 0 entries, got $N_TODAY"

say "Reject future startDate (expect 400)"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"FutureLog\",\"unit\":\"minutes\",\"description\":\"\",\"startDate\":\"$TOMORROW\"}")
[ "$HTTP" = "400" ] && ok "future startDate rejected" || fail "future startDate should 400 (got $HTTP)"

say "Edit a backfilled skip entry (PUT /api/entries/:id)"
FIRST_SKIP_ID=$(echo "$GOT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["entries"][0]["id"])')
EDITED=$(curl -sS -b "$COOKIES" -X PUT "$BASE/api/entries/$FIRST_SKIP_ID" \
  -H "Content-Type: application/json" \
  -d '{"quantity":20,"description":"late edit"}')
EQ=$(echo "$EDITED" | python3 -c 'import sys,json; print(json.load(sys.stdin)["quantity"])')
ED=$(echo "$EDITED" | python3 -c 'import sys,json; print(json.load(sys.stdin)["description"])')
[ "$EQ" = "20.0" ] || [ "$EQ" = "20" ] && ok "skip entry quantity updated" || fail "edit quantity ($EQ)"
[ "$ED" = "late edit" ] && ok "skip entry description updated" || fail "edit description ($ED)"

say "Create log (minutes)"
LOG=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Running","unit":"minutes","description":"jogs"}')
LOG_ID=$(echo "$LOG" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
[ -n "$LOG_ID" ] && ok "created log $LOG_ID" || fail "create log"

say "List logs"
curl -sS -b "$COOKIES" "$BASE/api/logs" | grep -q "Running" && ok "list contains Running" || fail "list logs"

say "Post first entry (2026-04-10, quantity=30)"
R1=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-10","quantity":30,"description":"easy"}')
N1=$(echo "$R1" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N1" = "1" ] && ok "first entry inserted, total=1" || fail "first entry (got $N1)"

say "Post gap entry (2026-04-13) — expect 4 rows total (10, 11, 12, 13)"
R2=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-13","quantity":45,"description":"hard"}')
N2=$(echo "$R2" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N2" = "4" ] && ok "skip-fill gave 4 rows" || fail "skip-fill count (got $N2)"

SKIP_QTY=$(echo "$R2" | python3 -c '
import sys,json
es = json.load(sys.stdin)["entries"]
print([e["quantity"] for e in es if e["entryDate"]=="2026-04-11"][0])
')
[ "$SKIP_QTY" = "0.0" ] || [ "$SKIP_QTY" = "0" ] && ok "gap day has quantity 0" || fail "skip-fill quantity (got $SKIP_QTY)"

say "Same-day accumulate (post 2026-04-13 again, +15)"
R3=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-13","quantity":15,"description":""}')
ACC_QTY=$(echo "$R3" | python3 -c '
import sys,json
es = json.load(sys.stdin)["entries"]
print([e["quantity"] for e in es if e["entryDate"]=="2026-04-13"][0])
')
[ "$ACC_QTY" = "60.0" ] || [ "$ACC_QTY" = "60" ] && ok "accumulated to 60" || fail "accumulate (got $ACC_QTY)"

say "Back-fill accumulate onto a skip (post 2026-04-11, +20)"
R4=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-11","quantity":20,"description":"upgraded from skip"}')
UPG=$(echo "$R4" | python3 -c '
import sys,json
es = json.load(sys.stdin)["entries"]
print([e["quantity"] for e in es if e["entryDate"]=="2026-04-11"][0])
')
[ "$UPG" = "20.0" ] || [ "$UPG" = "20" ] && ok "skip upgraded to 20" || fail "back-fill (got $UPG)"

say "Reject unit change when entries exist"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X PUT "$BASE/api/logs/$LOG_ID" \
  -H "Content-Type: application/json" \
  -d '{"name":"Running","description":"jogs","unit":"hours"}')
[ "$HTTP" = "400" ] && ok "unit change rejected (400)" || fail "unit change should 400 (got $HTTP)"

say "Delete log"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/logs/$LOG_ID")
[ "$HTTP" = "204" ] && ok "delete 204" || fail "delete log (got $HTTP)"

say "Streak tracking"

# Fresh log starting today.
LOG_S=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Streaks","unit":"minutes","description":""}')
LOG_S_ID=$(echo "$LOG_S" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

post_entry() {
  local date="$1" qty="$2"
  curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_S_ID/entries" \
    -H "Content-Type: application/json" \
    -d "{\"entryDate\":\"$date\",\"quantity\":$qty,\"description\":\"\"}" \
    > /dev/null
}

get_stats() {
  curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_S_ID" \
    | python3 -c '
import sys, json
s = json.load(sys.stdin)["streakStats"]
cur = s["current"]
lng = s["longest"]
avg = "null" if s["average"] is None else "%.1f" % float(s["average"])
print("%s|%s|%s" % (cur, avg, lng))
'
}

# macOS/Linux date helpers already defined earlier in the script; compute 5 days worth.
if date -u -v-4d +%Y-%m-%d >/dev/null 2>&1; then
  D0=$(date -u -v-4d +%Y-%m-%d)
  D1=$(date -u -v-3d +%Y-%m-%d)
  D2=$(date -u -v-2d +%Y-%m-%d)
  D3=$(date -u -v-1d +%Y-%m-%d)
  D4=$TODAY
else
  D0=$(date -u -d '4 days ago' +%Y-%m-%d)
  D1=$(date -u -d '3 days ago' +%Y-%m-%d)
  D2=$(date -u -d '2 days ago' +%Y-%m-%d)
  D3=$(date -u -d '1 day ago'  +%Y-%m-%d)
  D4=$TODAY
fi

# Three consecutive qty>0 entries: D0, D1, D2.
post_entry "$D0" 5
post_entry "$D1" 5
post_entry "$D2" 5

STATS=$(get_stats)
[ "$STATS" = "3|3.0|3" ] && ok "three-day streak: current=3, avg=3, longest=3" \
  || fail "expected 3|3.0|3, got $STATS"

# Post a skip (qty=0) for D3 — most-recent streak length should still read 3
# (rest-day tolerant: "current" = length of most recent streak, not 0).
post_entry "$D3" 0

STATS=$(get_stats)
[ "$STATS" = "3|3.0|3" ] && ok "skip day keeps current=3 (rest-day tolerant)" \
  || fail "expected 3|3.0|3 after skip, got $STATS"

# Post qty>0 for D4 — a new 1-day streak starts.
post_entry "$D4" 5

STATS=$(get_stats)
[ "$STATS" = "1|2.0|3" ] && ok "after new entry: current=1, avg=2, longest=3" \
  || fail "expected 1|2.0|3, got $STATS"

# Update D3 (the skip) to qty>0 — streaks merge into a single 5-day run.
D3_ID=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_S_ID" \
  | python3 -c "import sys,json; es=json.load(sys.stdin)['entries']; print(next(e for e in es if e['entryDate']=='$D3')['id'])")
curl -sS -b "$COOKIES" -X PUT "$BASE/api/entries/$D3_ID" \
  -H "Content-Type: application/json" \
  -d '{"quantity":5,"description":""}' > /dev/null

STATS=$(get_stats)
[ "$STATS" = "5|5.0|5" ] && ok "update skip→qty>0 merges streaks: 5|5.0|5" \
  || fail "expected 5|5.0|5, got $STATS"

# Empty log: a log with no qty>0 entries has current=0, avg=null, longest=0.
LOG_E=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Empty","unit":"minutes","description":""}')
LOG_E_ID=$(echo "$LOG_E" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
EMPTY=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_E_ID" \
  | python3 -c '
import sys, json
s = json.load(sys.stdin)["streakStats"]
cur = s["current"]
lng = s["longest"]
avg = "null" if s["average"] is None else "%.1f" % float(s["average"])
print("%s|%s|%s" % (cur, avg, lng))
')
[ "$EMPTY" = "0|null|0" ] && ok "empty log: 0|null|0" \
  || fail "expected 0|null|0, got $EMPTY"

say "Logout"
HTTP=$(curl -sS -b "$COOKIES" -c "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/auth/logout")
[ "$HTTP" = "204" ] && ok "logout 204" || fail "logout (got $HTTP)"

say "Me after logout should 401"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" "$BASE/api/auth/me")
[ "$HTTP" = "401" ] && ok "me is 401 after logout" || fail "me post-logout (got $HTTP)"

echo ""
echo "ALL CHECKS PASSED"
