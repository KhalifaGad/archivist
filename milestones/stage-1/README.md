# Stage 1 — A typed event store on SQLite

## Where you are coming in

- Fresh Haskell. You may not have GHC installed. Surface-level memory of syntax at best.
- No prior database internals knowledge.
- Limited free time — lessons are sized for one focused evening.

## Where you'll be at the end

You'll have shipped a working Haskell project that:

- Stores immutable events in named streams, **persisted in SQLite** so they survive restarts
- Encodes seal status (`Sealed` / `Unsigned`) as a **phantom type** — calling `verify` on an unsigned stream is a *compile error*
- Maintains a **cryptographic hash chain** on sealed streams
- Has a real test suite, including **property-based tests** proving the append-only and hash-chain invariants
- Comes with a tiny CLI demo and a README good enough to share

Along the way you will have learned: types, ADTs, pattern matching, IO, modules and Cabal, `Maybe`/`Either`, typeclasses, folds, phantom types, GADTs, basic cryptography in Haskell, `sqlite-simple`, Hspec, and QuickCheck.

## What you will *not* learn in Stage 1

- Custom storage engines, WAL, fsync semantics, memory-mapped files — that's Stage 2, deliberately. SQLite is a scaffold; we throw it away later without guilt.
- STM and concurrent appends — Stage 2 territory. Stage 1 is single-threaded by design so the type system stays the focus.
- Wire protocols, query languages — Stage 3.

## How a lesson is shaped

Every lesson directory contains:

- `README.md` — the lesson itself, structured as:
  1. **Where you are** — what you should be able to do walking in
  2. **Learning goal** — the one concept you'll internalize
  3. **Delivery goal** — what you'll ship
  4. **Concept warm-up** — short exercises in GHCi or a scratch file (don't skip these)
  5. **Build it** — the actual work
  6. **Verify** — how to know you're done
  7. **Self-check** — questions; if you can answer them you're ready for the next lesson
  8. **Stretch** — optional rabbit hole
- A verification target:
  - Lessons 0–3: a `check.hs` you run with `runghc check.hs`. Prints `PASS ✓` when you're done.
  - Lessons 4+: a Cabal test suite. Verification is `cabal test`. The `check.hs` from this point on is just a thin wrapper that calls it.

## Project layout across lessons

The project lives in **two different places** depending on where you are in the stage. This is deliberate — the early lessons keep things minimal so you can focus on Haskell itself; the real project layout arrives in Lesson 4 once you have enough Haskell under your belt to appreciate it.

**Lesson 0 — throwaway script.**
- `hello.hs` lives inside `00-setup/`. It's a one-off — never imported, never grown.

**Lessons 1–3 — single growing file, scoped per lesson.**
- Your code (`Archivist.hs`, and from L3 also `Main.hs`) lives inside each lesson's directory.
- When you start a new lesson, **copy the previous lesson's `.hs` files into the new lesson's directory**, then evolve them in place.
- This means each lesson directory is a self-contained checkpoint — if you want to revisit Lesson 2's exact state, it's still there, untouched.
- Why not modules / Cabal yet? Because forcing `cabal init`, `.cabal` syntax, dependency declarations, and module path conventions on top of "what is a type signature" doubles the cognitive load. One new thing per lesson.

**Lesson 4 onward — the real Cabal project at the repo root.**
- The project moves to the **repo root**, in the standard Haskell layout:
  ```
  archivist/                       <-- repo root
  ├── archivist.cabal
  ├── src/Archivist/Event.hs       module Archivist.Event
  ├── src/Archivist/Stream.hs      module Archivist.Stream
  ├── app/Main.hs                  the demo executable
  ├── test/Spec.hs                 Hspec entry point
  └── milestones/...               (this directory)
  ```
- From L4 to the end of Stage 1, **all your code goes into the repo-root project.** The project keeps growing — you do not copy-and-evolve per lesson anymore.
- Lesson directories from L4 onward contain only `README.md` (the lesson) and `check.hs` (a thin wrapper that calls `cabal test` against the repo-root project).
- This matches real Haskell project structure exactly: Cabal package, modular layout under `src/`, executable in `app/`, test-suite in `test/`. You'll be living in this layout for the rest of Stage 1 and all of Stages 2 and 3.

The transition in L4 is itself part of the learning: you'll feel the friction of the loose-file approach right before Cabal solves it.

## Tone and method

Tutor style — explanation first, then *try this*, then *now build*. Tests are written **before** the implementation guide whenever practical. Read the tests first; they're the spec.

Three rules:

1. **Try it yourself before asking Claude.** The struggle is the learning. If you're stuck after ~15 minutes, ask.
2. **Don't skip the warm-up.** It's there to make the build phase feel obvious instead of magical.
3. **Don't move on with a yellow verification.** If a test is failing or skipped, fix it before the next lesson. Skipped tests rot fast.

## How to use Claude alongside this

This roadmap is the spine. Use Claude as a tutor when:

- A concept doesn't click — ask for an alternate explanation, simpler analogy, or worked example.
- You hit a type error you can't read — paste it and ask what it means in plain English.
- You want to understand *why* a Haskell idiom exists, not just *how* to use it.

Avoid asking Claude to write the lesson's deliverable for you. The point is your hands on the keyboard.

## The three acts

| Act | Lessons | Theme |
|---|---|---|
| I — *It runs* | 0–4 | Haskell from zero to a real Cabal project |
| II — *It's a real event store* | 5–9 | The typed model, climaxing in the GADT seal-status showpiece |
| III — *It survives a crash* | 10–13 | Persistence, hashing, property tests, capstone |

## Lesson index

| # | Lesson | Learning | Deliverable |
|---|---|---|---|
| 0 | [Setup](00-setup/README.md) | Toolchain + GHCi fluency | `hello.hs` that compiles and runs |
| 1 | [Values & types](01-values-and-types/README.md) | Type signatures, tuples, type aliases | First `Event` (as a tuple) + `appendEvent` |
| 2 | [ADTs & pattern matching](02-adts-and-pattern-matching/README.md) | `data`, records, sum types | `Event` as a record, `Stream`, `SealStatus` foreshadowed |
| 3 | [IO and pure](03-io-and-pure/README.md) | `IO`, do-notation, the pure/effectful split | Runnable `main` that builds and prints a stream |
| 4 | [A real Cabal project](04-cabal-project/README.md) | Modules, packages, Hspec | Cabal project with `cabal test` green |
| 5 | [Maybe & Either](05-maybe-and-either/README.md) | Total functions, errors without exceptions | `lookupEvent`, `findByPayload`, `Archivist.Validation` |
| 6 | [Typeclasses](06-typeclasses/README.md) | `Show`/`Eq`/`Ord`, deriving, instances | Custom `Show`, `Archivist.Identifiable` |
| 7 | [Folds](07-folds/README.md) | Recursion → `foldl'` | `replay` + `Archivist.Projection` |
| 8 | [Phantom types](08-phantom-types/README.md) | Types as proofs | `Stream e s` parameterized by seal status |
| 9 | [GADTs](09-gadts/README.md) | Type-level evidence | `EventStream` GADT; `verify` only compiles on `Sealed` |
| 10 | [Hashing & the chain](10-hashing-and-the-chain/README.md) | `cryptonite`, hash chains | Real cryptographic seal + tamper-evident `verify` |
| 11 | [SQLite persistence](11-sqlite-persistence/README.md) | `sqlite-simple`, schema design | Events survive program restart |
| 12 | [QuickCheck](12-quickcheck/README.md) | Property-based testing | Properties for append-only, chain integrity, round-trip |
| 13 | [Capstone](13-capstone/README.md) | Integration & reflection | CLI demo + project README + `stage-1-complete` tag |

## Progress tracker

Tick each box as you finish. (You can edit this file freely — it's yours.)

- [ ] 0 — Setup
- [ ] 1 — Values & types
- [ ] 2 — ADTs & pattern matching
- [ ] 3 — IO and pure
- [ ] 4 — A real Cabal project
- [ ] 5 — Maybe & Either
- [ ] 6 — Typeclasses
- [ ] 7 — Folds
- [ ] 8 — Phantom types
- [ ] 9 — GADTs
- [ ] 10 — Hashing & the chain
- [ ] 11 — SQLite persistence
- [ ] 12 — QuickCheck
- [ ] 13 — Capstone

## When you finish Stage 1

We design Stage 2 (the custom append-only storage engine + WAL + STM concurrency) from a position of strength. You'll already understand the typed model, so the storage layer becomes the entire focus instead of competing with Haskell-as-a-language for attention.
