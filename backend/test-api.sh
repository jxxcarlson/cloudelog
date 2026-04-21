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
  -d "{\"name\":\"Backfilled\",\"metrics\":[{\"name\":\"minutes\",\"unit\":\"minutes\"}],\"description\":\"\",\"startDate\":\"$THREE_DAYS_AGO\"}")
LOG_SD_ID=$(echo "$LOG_SD" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
SD_IN_RESP=$(echo "$LOG_SD" | python3 -c 'import sys,json; print(json.load(sys.stdin)["startDate"])')
[ "$SD_IN_RESP" = "$THREE_DAYS_AGO" ] && ok "startDate echoed in response" || fail "startDate response ($SD_IN_RESP)"

GOT=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_SD_ID")
N_ENTRIES=$(echo "$GOT" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N_ENTRIES" = "3" ] && ok "3 backfilled entries present" || fail "expected 3 entries, got $N_ENTRIES"
ALL_ZERO=$(echo "$GOT" | python3 -c 'import sys,json; es=json.load(sys.stdin)["entries"]; print(all(e["values"][0]["quantity"]==0 and e["values"][0]["description"]=="" for e in es))')
[ "$ALL_ZERO" = "True" ] && ok "all backfilled entries are zero/empty" || fail "backfilled entries not zero/empty"

say "Create log with no startDate (expect startDate == today, 0 entries)"
LOG_TODAY=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"TodayOnly","metrics":[{"name":"minutes","unit":"minutes"}],"description":""}')
LOG_TODAY_ID=$(echo "$LOG_TODAY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
SD_TODAY=$(echo "$LOG_TODAY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["startDate"])')
[ "$SD_TODAY" = "$TODAY" ] && ok "startDate defaults to today" || fail "default startDate ($SD_TODAY vs $TODAY)"
N_TODAY=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_TODAY_ID" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N_TODAY" = "0" ] && ok "no entries when startDate == today" || fail "expected 0 entries, got $N_TODAY"

say "Reject future startDate (expect 400)"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"FutureLog\",\"metrics\":[{\"name\":\"minutes\",\"unit\":\"minutes\"}],\"description\":\"\",\"startDate\":\"$TOMORROW\"}")
[ "$HTTP" = "400" ] && ok "future startDate rejected" || fail "future startDate should 400 (got $HTTP)"

say "Edit a backfilled skip entry (PUT /api/entries/:id)"
FIRST_SKIP_ID=$(echo "$GOT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["entries"][0]["id"])')
EDITED=$(curl -sS -b "$COOKIES" -X PUT "$BASE/api/entries/$FIRST_SKIP_ID" \
  -H "Content-Type: application/json" \
  -d '{"values":[{"quantity":20,"description":"late edit"}]}')
EQ=$(echo "$EDITED" | python3 -c 'import sys,json; print(json.load(sys.stdin)["values"][0]["quantity"])')
ED=$(echo "$EDITED" | python3 -c 'import sys,json; print(json.load(sys.stdin)["values"][0]["description"])')
[ "$EQ" = "20.0" ] || [ "$EQ" = "20" ] && ok "skip entry quantity updated" || fail "edit quantity ($EQ)"
[ "$ED" = "late edit" ] && ok "skip entry description updated" || fail "edit description ($ED)"

say "Create log (minutes)"
LOG=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Running","metrics":[{"name":"minutes","unit":"minutes"}],"description":"jogs"}')
LOG_ID=$(echo "$LOG" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
[ -n "$LOG_ID" ] && ok "created log $LOG_ID" || fail "create log"

say "List logs"
curl -sS -b "$COOKIES" "$BASE/api/logs" | grep -q "Running" && ok "list contains Running" || fail "list logs"

say "Post first entry (2026-04-10, quantity=30)"
R1=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-10","values":[{"quantity":30,"description":"easy"}]}')
N1=$(echo "$R1" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N1" = "1" ] && ok "first entry inserted, total=1" || fail "first entry (got $N1)"

say "Post gap entry (2026-04-13) — expect 4 rows total (10, 11, 12, 13)"
R2=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-13","values":[{"quantity":45,"description":"hard"}]}')
N2=$(echo "$R2" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["entries"]))')
[ "$N2" = "4" ] && ok "skip-fill gave 4 rows" || fail "skip-fill count (got $N2)"

SKIP_QTY=$(echo "$R2" | python3 -c '
import sys,json
es = json.load(sys.stdin)["entries"]
print([e["values"][0]["quantity"] for e in es if e["entryDate"]=="2026-04-11"][0])
')
[ "$SKIP_QTY" = "0.0" ] || [ "$SKIP_QTY" = "0" ] && ok "gap day has quantity 0" || fail "skip-fill quantity (got $SKIP_QTY)"

say "Same-day overwrite (post 2026-04-13 again, qty=7)"
curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_ID/entries" \
  -H "Content-Type: application/json" \
  -d '{"entryDate":"2026-04-13","values":[{"quantity":7,"description":""}]}' \
  > /dev/null
GOT_Q=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_ID" \
  | python3 -c 'import sys,json; es=json.load(sys.stdin)["entries"]; print(next(e for e in es if e["entryDate"]=="2026-04-13")["values"][0]["quantity"])')
[ "$GOT_Q" = "7" ] || [ "$GOT_Q" = "7.0" ] && ok "same-day POST overwrites to 7" || fail "expected 7, got $GOT_Q"

say "Reject unit change when entries exist"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X PUT "$BASE/api/logs/$LOG_ID" \
  -H "Content-Type: application/json" \
  -d '{"name":"Running","description":"jogs","metrics":[{"name":"minutes","unit":"hours"}]}')
[ "$HTTP" = "400" ] && ok "unit change rejected (400)" || fail "unit change should 400 (got $HTTP)"

say "Delete log"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/logs/$LOG_ID")
[ "$HTTP" = "204" ] && ok "delete 204" || fail "delete log (got $HTTP)"

say "Streak tracking"

# Fresh log starting today.
LOG_S=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Streaks","metrics":[{"name":"minutes","unit":"minutes"}],"description":""}')
LOG_S_ID=$(echo "$LOG_S" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

post_entry() {
  local date="$1" qty="$2"
  curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_S_ID/entries" \
    -H "Content-Type: application/json" \
    -d "{\"entryDate\":\"$date\",\"values\":[{\"quantity\":$qty,\"description\":\"\"}]}" \
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
  -d '{"values":[{"quantity":5,"description":""}]}' > /dev/null

STATS=$(get_stats)
[ "$STATS" = "5|5.0|5" ] && ok "update skip→qty>0 merges streaks: 5|5.0|5" \
  || fail "expected 5|5.0|5, got $STATS"

# Empty log: a log with no qty>0 entries has current=0, avg=null, longest=0.
LOG_E=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Empty","metrics":[{"name":"minutes","unit":"minutes"}],"description":""}')
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

say "Multi-metric log"
LOG_M=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H "Content-Type: application/json" \
  -d '{"name":"Running","metrics":[{"name":"distance","unit":"miles"},{"name":"time","unit":"minutes"}],"description":""}')
LOG_M_ID=$(echo "$LOG_M" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
N_METRICS=$(echo "$LOG_M" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["metrics"]))')
[ "$N_METRICS" = "2" ] && ok "multi-metric log has 2 metrics" || fail "expected 2, got $N_METRICS"

# Reject wrong-length values array.
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/logs/$LOG_M_ID/entries" \
  -H "Content-Type: application/json" \
  -d "{\"entryDate\":\"$TODAY\",\"values\":[{\"quantity\":3.2,\"description\":\"easy\"}]}")
[ "$HTTP" = "400" ] && ok "wrong-length values rejected" || fail "expected 400, got $HTTP"

# Accept correct-length values.
POSTED=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs/$LOG_M_ID/entries" \
  -H "Content-Type: application/json" \
  -d "{\"entryDate\":\"$TODAY\",\"values\":[{\"quantity\":3.2,\"description\":\"easy\"},{\"quantity\":27.5,\"description\":\"\"}]}")
N_VALS=$(echo "$POSTED" | python3 -c 'import sys,json; es=json.load(sys.stdin)["entries"]; print(len(es[0]["values"]))')
[ "$N_VALS" = "2" ] && ok "entry carries 2 values" || fail "expected 2, got $N_VALS"

say "Collections"

# Create an empty collection.
COLL=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/collections" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Piano practice","description":"daily work"}')
COLL_ID=$(echo "$COLL" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

# Create two single-metric minutes logs and assign both to the collection.
LOG_1=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Sight reading","metrics":[{"name":"minutes","unit":"minutes"}],"description":""}')
LOG_1_ID=$(echo "$LOG_1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
LOG_2=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/logs" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Harmony","metrics":[{"name":"minutes","unit":"minutes"}],"description":""}')
LOG_2_ID=$(echo "$LOG_2" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

curl -sS -b "$COOKIES" -X PUT "$BASE/api/logs/$LOG_1_ID/collection" \
  -H 'Content-Type: application/json' \
  -d "{\"collectionId\":\"$COLL_ID\"}" > /dev/null
curl -sS -b "$COOKIES" -X PUT "$BASE/api/logs/$LOG_2_ID/collection" \
  -H 'Content-Type: application/json' \
  -d "{\"collectionId\":\"$COLL_ID\"}" > /dev/null

# List collections — expect memberCount = 2.
COUNT=$(curl -sS -b "$COOKIES" "$BASE/api/collections" \
  | python3 -c "import sys,json; c=next(x for x in json.load(sys.stdin) if x['id']=='$COLL_ID'); print(c['memberCount'])")
[ "$COUNT" = "2" ] && ok "collection has 2 members" || fail "expected 2 members, got $COUNT"

# POST combined entry — LOG_1 gets 15 min, LOG_2 gets a skip.
RESP=$(curl -sS -b "$COOKIES" -X POST "$BASE/api/collections/$COLL_ID/entries" \
  -H 'Content-Type: application/json' \
  -d "{\"entryDate\":\"$TODAY\",\"logEntries\":[
        {\"logId\":\"$LOG_1_ID\",\"values\":[{\"quantity\":15,\"description\":\"Clementi\"}]},
        {\"logId\":\"$LOG_2_ID\",\"values\":[{\"quantity\": 0,\"description\":\"\"}]}
      ]}")

# Assert both members have today's entry.
N1=$(echo "$RESP" | python3 -c "
import sys,json
d = json.load(sys.stdin)
for m in d['members']:
    if m['log']['id']=='$LOG_1_ID':
        e = [e for e in m['entries'] if e['entryDate']=='$TODAY']
        print(e[0]['values'][0]['quantity'] if e else 'MISSING')
        break
")
[ "$N1" = "15" ] || [ "$N1" = "15.0" ] && ok "LOG_1 today = 15" || fail "expected 15, got $N1"

N2=$(echo "$RESP" | python3 -c "
import sys,json
d = json.load(sys.stdin)
for m in d['members']:
    if m['log']['id']=='$LOG_2_ID':
        e = [e for e in m['entries'] if e['entryDate']=='$TODAY']
        print(e[0]['values'][0]['quantity'] if e else 'MISSING')
        break
")
[ "$N2" = "0" ] || [ "$N2" = "0.0" ] && ok "LOG_2 today = 0 (skip)" || fail "expected 0, got $N2"

# Wrong-length values should 400.
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/collections/$COLL_ID/entries" \
  -H 'Content-Type: application/json' \
  -d "{\"entryDate\":\"$TODAY\",\"logEntries\":[
        {\"logId\":\"$LOG_1_ID\",\"values\":[]}
      ]}")
[ "$HTTP" = "400" ] && ok "empty values rejected" || fail "expected 400, got $HTTP"

# Release LOG_2 from the collection, verify it's standalone.
curl -sS -b "$COOKIES" -X PUT "$BASE/api/logs/$LOG_2_ID/collection" \
  -H 'Content-Type: application/json' \
  -d '{"collectionId":null}' > /dev/null
REMAINING=$(curl -sS -b "$COOKIES" "$BASE/api/collections/$COLL_ID" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["members"]))')
[ "$REMAINING" = "1" ] && ok "release log leaves 1 member" || fail "expected 1, got $REMAINING"

# Delete collection; the still-attached log should release to standalone.
curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/collections/$COLL_ID" > /dev/null
RELEASED=$(curl -sS -b "$COOKIES" "$BASE/api/logs/$LOG_1_ID" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["log"]["collectionId"])')
[ "$RELEASED" = "None" ] && ok "deleted collection releases members" || fail "expected None, got $RELEASED"

say "Logout"
HTTP=$(curl -sS -b "$COOKIES" -c "$COOKIES" -o /dev/null -w "%{http_code}" -X POST "$BASE/api/auth/logout")
[ "$HTTP" = "204" ] && ok "logout 204" || fail "logout (got $HTTP)"

say "Me after logout should 401"
HTTP=$(curl -sS -b "$COOKIES" -o /dev/null -w "%{http_code}" "$BASE/api/auth/me")
[ "$HTTP" = "401" ] && ok "me is 401 after logout" || fail "me post-logout (got $HTTP)"

echo ""
echo "ALL CHECKS PASSED"
