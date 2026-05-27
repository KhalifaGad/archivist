# Lesson 13 — Capstone: a real demo, a README, and a reflection

## Where you are

You have a typed event store. Phantom-typed seal status hardened into a GADT. A cryptographic hash chain. SQLite persistence. Property-based proofs of your core invariants. Twelve evenings of work.

This last lesson isn't new Haskell. It's the *integration*: a CLI demo that exercises everything, a project README good enough to share, and a short written reflection.

If Stage 1 is a hike, this is the summit photo.

## Learning goal

- Practice integrating disparate modules behind one entry point
- Write a project README that's honest, scannable, and useful to a future you
- Reflect deliberately on what you learned — what surprised, what stuck, what's still hand-wavy
- Set yourself up for Stage 2 with a clean baseline

## Delivery goal

1. **Update `app/Main.hs` into a meaningful demo.** Sequence: open a fresh SQLite store → build an unsigned stream → persist it → load it back → seal a *separate* stream → verify it → tamper with it in-memory → fail verify visibly → print a summary. The exact narrative is yours; the test below checks for specific substrings in the output.
2. **Write `README.md` at the repo root** — the *project's* README (not the curriculum's). It should let a stranger (or future you) understand what Archivist is, what works in Stage 1, and how to run the demo.
3. **Write `REFLECTION.md` at the repo root** — your private journal entry on Stage 1. Honest about what stuck and what didn't.
4. **Tag the repo** — `git tag stage-1-complete`. Symbolic, satisfying, and useful as a baseline before Stage 2's storage-engine work overwrites half the codebase.

---

## Build the demo (60–90 min)

Replace `app/Main.hs` with something like this. *Don't copy verbatim* — make it your own, especially the printed lines:

```haskell
{-# LANGUAGE TypeApplications #-}
module Main where

import System.IO (hSetBuffering, stdout, BufferMode(..))
import Database.SQLite.Simple (close)

import Archivist.Event
import Archivist.Stream
import Archivist.Storage.SQLite

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  putStrLn "=== Archivist demo ==="

  -- 1. Open a fresh in-process SQLite store
  putStrLn "\n[1] Opening store at /tmp/archivist-demo.db ..."
  conn <- openStore "/tmp/archivist-demo.db"

  -- 2. Build an unsigned stream and persist it
  putStrLn "\n[2] Building unsigned stream 'orders' with 3 events..."
  let e1 = mkEvent "order-placed"     "evt-1" "2024-01-01T10:00:00Z"
      e2 = mkEvent "payment-received" "evt-2" "2024-01-01T10:05:00Z"
      e3 = mkEvent "shipped"          "evt-3" "2024-01-01T11:30:00Z"
      ordersUnsigned =
        appendUnsigned e3
        . appendUnsigned e2
        . appendUnsigned e1
        $ emptyUnsigned "orders"

  mapM_ (\(i, e) -> persistUnsignedEvent conn "orders" e i)
        (zip [0..] [e1, e2, e3])
  putStrLn "    persisted."

  -- 3. Load it back, verify the count matches
  putStrLn "\n[3] Loading 'orders' from SQLite ..."
  loaded <- loadUnsigned conn "orders"
  putStrLn ("    loaded " ++ show (eventCount loaded) ++ " events.")

  -- 4. Build a *sealed* stream and verify
  putStrLn "\n[4] Building and sealing stream 'audit' ..."
  let auditUnsigned =
        appendUnsigned (mkEvent "user-login" "evt-a" "t1")
        . appendUnsigned (mkEvent "role-changed" "evt-b" "t2")
        $ emptyUnsigned "audit"
      auditSealed = sealStream auditUnsigned

  putStrLn ("    sealed. verify = " ++ show (verify auditSealed))

  -- 5. Tamper and watch verify fail
  putStrLn "\n[5] Tampering with the first event's payload ..."
  let tampered = case auditSealed of
        SealedStream sid (se:rest) ->
          SealedStream sid
            (se { sealedEvent = (sealedEvent se) { payload = "EVIL" } } : rest)
        other -> other
  putStrLn ("    after tamper, verify = " ++ show (verify tampered))

  -- 6. Summary
  putStrLn "\n=== summary ==="
  putStrLn "  - unsigned round-trip: OK"
  putStrLn "  - seal + verify happy path: OK"
  putStrLn "  - tamper detected by verify: OK"

  close conn
```

Run:

```sh
cabal run archivist-demo
```

The output should narrate every step. That's what makes the demo demo-able.

---

## Write the project README

Create `README.md` at the **repo root**. The structure I'd suggest:

```markdown
# Archivist

A typed, hierarchical, append-only event store with optional cryptographic sealing — built in Haskell.

## Status

**Stage 1 complete.** A working typed event store backed by SQLite, with:

- Phantom-typed seal status (`Sealed` / `Unsigned`) enforced at the type level via GADTs
- SHA-256 hash chain on sealed streams
- SQLite persistence with full round-trip tests
- Property-based tests proving append-only and chain-integrity invariants

Custom storage engine + WAL coming in Stage 2.

## Run the demo

\`\`\`sh
cabal run archivist-demo
\`\`\`

## Run the tests

\`\`\`sh
cabal test
\`\`\`

## Project structure

- `src/Archivist/Event.hs` — the immutable event type
- `src/Archivist/Stream.hs` — the GADT-backed stream with seal-status invariants
- `src/Archivist/Hash.hs` — SHA-256 hash chain
- `src/Archivist/Storage/SQLite.hs` — durable storage
- `src/Archivist/Validation.hs` — event-level validation
- `src/Archivist/Projection.hs` — example projections built on `replay`

## Design philosophy

See [project_context.md](project_context.md) for the long version. In short:

- Events are immutable facts, not entity snapshots
- Schema evolution is by emitting new events, not by migrating old ones
- Sealing is opt-in per stream — zero overhead until you need tamper-evidence
- `verify` only type-checks on `Sealed` streams (compile error otherwise)

## License

MIT (or whatever you prefer).
```

Customize freely. Make it the README *you* want to point a friend at.

---

## Write `REFLECTION.md`

Create `REFLECTION.md` at the repo root. This one's for you. Suggested prompts (skip what doesn't resonate):

```markdown
# Stage 1 reflection

## What clicked

- (one thing per bullet)

## What I still find hand-wavy

- (be honest — knowing what you don't know is half the value)

## Lessons I'd rewrite if I were teaching this to me

## Surprises

## The Haskell idea that changed how I think

## Energy: where it ran high, where it ran low

## What I want from Stage 2
```

Don't skip this. Future you, six months from now reading it, will thank present you.

---

## Tag the baseline

```sh
git add -A
git commit -m "Stage 1 complete: typed event store on SQLite"
git tag stage-1-complete
```

You now have a named checkpoint. When Stage 2 starts ripping out SQLite and replacing it with a custom storage engine, `git diff stage-1-complete..HEAD` will tell the story cleanly.

---

## Verify

```sh
runghc check.hs
```

The verification for L13 checks two things: (1) `cabal test` is still green; (2) `cabal run archivist-demo` produces output containing key narrative strings (`verify = True`, `verify = False` after tamper, etc.).

Skim the output of `cabal run archivist-demo` yourself. Reading the demo top-to-bottom is a small ceremony at the end of Stage 1.

---

## Design choices baked into this lesson

- **The demo is *narrated*, not silent** — it prints what it's doing at each step. Real CLIs would have flags (`--verbose`, `--quiet`); we hardcode verbose because the *point* of the demo is being readable.
- **`/tmp/archivist-demo.db` is hardcoded** — fine for a demo, terrible for production. The Stretch suggests a real CLI parser.
- **The tamper step reaches into the `SealedStream` constructor** — only possible because Lesson 10 chose to export the constructor (Option A). If you went Option B (`Internal` module), import that here.
- **`REFLECTION.md` is private** — `.gitignore` it if you don't want it in version control. I left it git-tracked because the prompts are useful to share with future learners.
- **`stage-1-complete` is a lightweight tag, not annotated** — `git tag -a stage-1-complete -m "..."` makes it annotated. Lightweight is fine here.
- **No CI** — no GitHub Actions, no automated testing on push. Stage 3 territory. Hand-running `cabal test` is the bar for now.

---

## Self-check (the Stage 1 retrospective)

You should be able to answer these from memory. If not, the lesson hasn't sunk in yet — revisit before Stage 2.

1. Why is `verify` a *compile error* on `EventStream e Unsigned`? Name the language feature that makes this work.
2. Why is `replay` "just a fold"?
3. What property of cryptographic hashes makes the chain tamper-evident?
4. What's the difference between an example test and a property test, and when does each shine?
5. The current storage layer uses SQLite. Why is the project context calling this a *scaffold*?

---

## Stretch

- **Real CLI:** replace the hardcoded demo with `optparse-applicative` for argument parsing. Subcommands: `append`, `seal`, `verify`, `list-streams`. Now you have a usable tool.
- **Snapshot slot:** add `data Snapshot s = Snapshot { atPosition :: Int, state :: s }` and a `restoreFromSnapshot :: Snapshot s -> EventStream e Sealed -> s` helper. The plumbing prepares the project for the snapshotting work hinted at in `project_context.md`'s performance section.
- **Hash algorithm swap:** generalize `Archivist.Hash` to be parameterized by a hash algorithm. Then make the demo run *both* SHA-256 and BLAKE2b versions and time them with `Data.Time.getCurrentTime`. Real numbers ground future decisions.
- **Publish:** push the repo to GitHub, write a short blog post about Stage 1, link the most beautiful lesson (probably L9). The community shows up for thoughtful learn-in-public posts in Haskell more than most ecosystems.

---

## Done?

`cabal test` green + `cabal run archivist-demo` narrates the full flow + `README.md` exists + `REFLECTION.md` exists + tag pushed → **Stage 1 complete.**

Open a new conversation with Claude when you're ready and we'll design Stage 2 together — the custom append-only storage engine, the simplified WAL, fsync semantics, and STM-backed concurrent appends. The fun part.

Congratulations.
