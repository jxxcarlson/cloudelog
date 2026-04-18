# cloudelog

## Design
See `docs/superpowers/specs/2026-04-18-cloudelog-design.md` for the current design spec. Treat it as authoritative; flag anything in the code that diverges.

## Stack
- Language: (Elm / Haskell / Agda / Python — fill in as decided)
- Build: (e.g., `elm make`, `cabal build`, `agda`, `pytest`)
- Tests: (command to run the test suite)

## Conventions
- Keep modules small and well-typed.
- Prefer total functions; document any partial ones.
- No new dependencies without a note in the spec.

## Workflow
- Plan mode for anything non-trivial — approve the plan before execution.
- After edits, run the typechecker; fix errors before proceeding.
