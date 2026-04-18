# cloudelog

Daily quantity logs (time, distance, pages, reps).

See `docs/superpowers/specs/2026-04-18-cloudelog-design.md` for the design spec
and `docs/superpowers/plans/2026-04-18-cloudelog.md` for the implementation plan.

## Dev quickstart

```
createdb cloudelog_dev
scripts/migrate.sh up
scripts/be_restart.sh        # backend on :8081
scripts/fe_restart.sh        # frontend on :8011
open http://localhost:8011
```
