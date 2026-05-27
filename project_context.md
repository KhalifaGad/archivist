# Archivist — Project Context

> **One-liner:** A typed, hierarchical, append-only event store with optional cryptographic sealing — built in Haskell.
>
> **Two modes, one engine:** works as a standard event sourcing database out of the box; opt into cryptographic sealing per-stream when tamper-evidence is required.

---

## The Honest Goal

Build a database from scratch in Haskell. Understand how databases actually work — storage engines, WAL, crash recovery, append-only logs. Use a language that makes the engineering genuinely fun. Everything else (market, product, fundability) is secondary and can come later if the project earns it.

---

## The Core Idea

An append-only event store where:

- Events are immutable facts — written once, never modified
- The log is strictly sequential — append only, no updates, no deletes
- Cryptographic sealing is **opt-in per stream** — zero overhead when not needed, tamper-evident proof when enabled
- The wire protocol is language-agnostic — clients don't know or care it's Haskell underneath

```
Stream (Unsigned mode)              Stream (Sealed mode)
├── Event A  (immutable fact)       ├── Event A  (immutable fact) [hash]
├── Event B  (immutable fact)       ├── Event B  (immutable fact) [hash]
└── Event C  (immutable fact)       └── Event C  (immutable fact) [hash]
                                         each hash covers the fact +
                                         hash of previous event
```

### Sealing modes

| Mode | Description | Use case |
|---|---|---|
| `Unsigned` | Append-only, immutable, no crypto overhead | Standard event sourcing |
| `Sealed` | Everything in Unsigned + cryptographic hash chain | Compliance, audit, tamper-evidence |

### Stream upgrade path

- **Unsigned → Sealed:** Allowed. New events get sealed. Old events get an `UnsignedLegacy` marker — still immutable, just not cryptographically proven. Auditors see exactly where the trust boundary starts.
- **Sealed → Unsigned:** Not allowed. Trust guarantees cannot be removed once established.
- **Retroactive sealing:** Not allowed. Signing events that were created without signatures would be dishonest.

### Key invariants

- Events are **never modified** after writing. Immutability is absolute.
- The log is **append-only** — no updates, no deletes, ever.
- In Sealed mode, the **hash chain** covers each fact and references the previous event's hash — tamper anywhere and verification fails.

---

## What This Is Not

- Not a general-purpose relational database
- Not a key-value store
- Not a blockchain or cryptocurrency project
- Not a competitor to Postgres
- Not trying to replace Kafka

---

## Event Sourcing Design Philosophy

Events are **domain facts recorded as understood at the moment they occurred** — not entity state snapshots.

This has a specific implication: **schema evolution is handled by emitting new events, not by migrating old ones.**

```
-- 2022: currency wasn't a concept yet
OrderPlaced { amount: 450 }

-- 2024: currency matters now -- emit a new fact, don't touch the old one
CurrencyContextAdded { orderId: 123, currency: "EGP" }
```

The fold that reconstructs state handles both event shapes. Old events remain historically accurate. No upcasting, no migration engine, no schema versioning machinery needed.

This keeps the database's job simple and honest: **store facts durably, retrieve them reliably, prove they haven't been tampered with if asked.**

---

## Why Haskell

Not a forced pairing. Haskell is genuinely well-suited to this problem:

| Concern | Haskell fit |
|---|---|
| Immutable data by default | Perfect — aligns with append-only semantics |
| Algebraic Data Types | Perfect — models events, stream entries, seal status cleanly |
| GADTs / Phantom Types | Perfect — `Stream Sealed` vs `Stream Unsigned` at the type level |
| STM (Software Transactional Memory) | Excellent — concurrent appends without deadlocks |
| Recursive folds | Natural — replaying a stream is just a fold |
| Cryptographic libraries | Good — `cryptonite` / `libsodium-bindings` are C under the hood |
| Property-based testing | Excellent — QuickCheck proves invariants across random inputs |
| Append-only sequential I/O | Acceptable — GC-friendly workload pattern |

### What Haskell features will be exercised

- **Algebraic Data Types** — modeling stream entries, events, seal status
- **GADTs / Phantom Types** — `EventStream e Sealed` vs `EventStream e Unsigned`; `verify` type-checks only on `Sealed` streams, calling it on `Unsigned` is a compile error
- **Type Classes** — `Appendable`, `Sealable`, `Verifiable` abstractions
- **STM** — concurrent appends to different streams without locks
- **Recursive folds** — stream replay is a left fold over immutable events
- **QuickCheck** — property-based tests for append-only invariants, hash chain integrity, round-trip correctness
- **Megaparsec** — query language (later stage)

### On Rust

Not needed now. The workload is append-only sequential writes — the most GC-friendly storage pattern. Cryptography is handled by C library bindings. If profiling reveals a bottleneck in the storage hot path, Rust can be added surgically for that layer only. Start pure Haskell.

---

## Storage Engine — The Real Learning

This is the most interesting part of the project — and the part that teaches database internals properly.

### Phase 1: SQLite as scaffold

Use SQLite (`sqlite-simple`) purely as a durable byte store while the typed model is being proven. Not the final answer — just removes the WAL problem temporarily so learning can focus on the event model and Haskell type machinery first.

Duration: a few weekends. Throw it away without guilt.

### Phase 2: Custom append-only log

Replace SQLite with a purpose-built log-structured storage engine. This is the real database internals work:

**On-disk format:**
```
[stream header] [event1 bytes] [event2 bytes] [event3 bytes] ...
```

Sequential reads are a single disk scan. Appends are always at the end. No B-tree, no query planner, no general-purpose overhead. The access pattern is maximally predictable — always append, always read sequentially or by ID.

**WAL (Write-Ahead Log):**
The WAL for an append-only store is significantly simpler than a general-purpose database WAL:
- Only one operation ever recorded: "append this entry here"
- Crash recovery rule: if the last WAL entry is incomplete, discard it
- Everything before it is valid — because you never update, only append

An incomplete append is simply dropped. No undo logic needed. This is the specific property of append-only stores that makes the WAL problem tractable.

**What you'll learn:**
- Log-structured storage and why it's fast for append workloads
- Memory-mapped files — reading large datasets without loading into memory
- WAL design — the simplified append-only version
- fsync semantics — when and why, what happens if you don't
- Page layout — packing variable-length records efficiently
- Crash recovery — proving the log is always in a valid state

### Phase 3: Performance (if needed)

If profiling shows the Haskell I/O path is the bottleneck, extract the storage engine to Rust behind an FFI boundary. The Haskell typed logic stays entirely untouched. This is a surgical addition, not a rewrite.

---

## Core Data Structures (initial sketch — subject to change)

```haskell
-- Sealing status encoded at the type level
data Sealed
data Unsigned

-- A single event in the log
data Event e = Event
  { payload   :: e
  , eventId   :: EventId
  , timestamp :: UTCTime
  , streamId  :: StreamId
  }

-- A stream with seal status as a phantom type
data EventStream e seal where
  UnsignedStream :: [Event e] -> EventStream e Unsigned
  SealedStream   :: [SealedEvent e] -> EventStream e Sealed

-- A sealed event — carries its hash and the previous hash
data SealedEvent e = SealedEvent
  { event    :: Event e
  , hash     :: Hash       -- covers this event's payload
  , prevHash :: Hash       -- covers previous event — forms the chain
  }

-- Legacy events when a stream is upgraded from Unsigned to Sealed
data LegacyEvent e = LegacyEvent
  { event :: Event e }     -- immutable, just not cryptographically proven

-- Core operations
append :: StreamId -> e -> IO ()
seal   :: EventStream e Unsigned -> IO (EventStream e Sealed)
verify :: EventStream e Sealed -> Bool  -- compile error on Unsigned streams
replay :: StreamId -> (s -> e -> s) -> s -> IO s

-- Upgrade a stream (new events sealed, old events marked UnsignedLegacy)
upgradeStream :: EventStream e Unsigned -> IO (EventStream e Sealed)
```

The key insight: **`verify` only type-checks on `Sealed` streams.** Calling it on an `Unsigned` stream is a compile error. The type system makes the wrong thing unrepresentable.

---

## Performance Considerations

**Snapshots:** Long streams are the real performance concern in event sourcing — not event complexity. Snapshots periodically materialize current state so replay starts from the snapshot, not event 1. The slot for snapshots should exist in the data model early even if not implemented yet.

**Projections:** The event store answers "what happened?" Read models (projections) answer "what is the current state?" These are separate. Fast reads come from projections, not from replaying the event store on every query.

**Lazy loading:** Don't load the full stream eagerly. Haskell's laziness model naturally supports loading events as the fold consumes them.

---

## Key Design Decisions Already Made

| Decision | Choice | Reason |
|---|---|---|
| Language | Haskell | Fun, fits the problem, exercises interesting features |
| Primary goal | Learn database internals + deepen Haskell | Honest about what this is |
| Cryptographic sealing | Opt-in per stream | Zero overhead until needed; honest upgrade path |
| Seal status | GADT phantom type | Illegal operations (verify on unsigned) are compile errors |
| Stream upgrade | Unsigned → Sealed only; no retroactive signing | Honest about when trust was established |
| Sub-streams | Not in core model | Good event modeling makes them unnecessary |
| Migration engine | Not in database | Schema evolution is handled by new events, not the DB |
| Storage phase 1 | SQLite scaffold | Get to the interesting Haskell faster |
| Storage phase 2 | Custom append-only log | The real learning; WAL is simpler for append-only |
| Rust | Not now; surgically later if needed | Profile first |
| Wire protocol | TBD (later) | HTTP/JSON or PostgreSQL-compatible |
| Crypto primitive | TBD | BLAKE3 or SHA-256 via `cryptonite` |
| Concurrency | STM | Composable, deadlock-free, Haskell-native |
| Testing | QuickCheck | Property-based — prove invariants hold across random inputs |

---

## Open Questions (to resolve during design/build)

- What is the exact on-disk binary format for events and stream headers?
- How does the hash chain handle the very first event in a sealed stream (no previous hash)?
- What does the WAL entry format look like for an append operation?
- How are `UnsignedLegacy` events represented on disk after a stream upgrade?
- What is the query language shape — SQL-like, or a custom typed DSL? (later)
- Should sealing be configurable as a global database default, or per-stream only?
- What is the snapshot format and when is snapshotting triggered?

---

## Market Context (not urgent — Stage 3 thinking)

The closest existing product is **EventStoreDB (now Kurrent)**:
- Written in C#/.NET
- No cryptographic tamper-evidence
- Small production footprint (~91 known users) despite a growing market

**immudb** (Codenotary) owns the cryptographic ledger space — open source, Merkle-backed, targets compliance use cases directly. Worth understanding as prior art.

**The honest positioning if this ever becomes a product:**
- Type-safe event sourcing is the moat (nobody owns it)
- Cryptographic sealing is the expansion story (immudb exists but is untyped)
- "Flip a flag when compliance arrives" is the adoption story

But none of this matters until the project is built and interesting to others.

**Profitability path:**
```
Stage 1: Build for fun and learning → open source it
Stage 2: If GitHub traction → write about it, grow community  
Stage 3: If companies use it → fundraising becomes a real conversation
```

---

## Personal Context

- **Background:** Staff Software Engineer, infrastructure-heavy (Kubernetes, Argo Rollouts, GCP, distributed systems)
- **Haskell experience:** Surface level — ADTs, basic syntax, no deep monads yet. Learned for fun ~5 years ago.
- **Goal:** Something fun that deepens Haskell knowledge and database internals understanding. Stays intellectually engaging long-term. Looks strong in a portfolio. Has a fundable path if it gets traction — but that's not the starting constraint.
- **Constraint:** Limited free time — needs to feel worth fighting for
- **Approach:** No hurry. Small deliverable pieces. Learn, enjoy, feel achievement at each stage.
- **Tooling:** Claude Code for implementation assistance and language learning

---

## What to Bring to Future Sessions

When starting a new session (with Claude or Claude Code), include this file and state your current focus. Example prompts:

- *"Here is my project context. Help me design a learning path broken into small deliverable milestones."*
- *"Here is my project context. I want to implement the core `EventStream` data structure with phantom types for seal status."*
- *"Here is my project context. I want to understand STM deeply enough to implement concurrent appends to different streams."*
- *"Here is my project context. Help me design the on-disk binary format for the append-only log."*
- *"Here is my project context. I want to implement the WAL for the custom storage engine."*
- *"Here is my project context. Help me write QuickCheck properties proving append-only and hash chain invariants."*