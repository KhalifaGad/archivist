# Lesson 11 — SQLite persistence: events that survive a restart

## Where you are

Your event store is fully typed and cryptographically chained — but every event evaporates the moment your program exits. A database that forgets its data isn't a database; it's a model.

This lesson is the moment Archivist becomes *real*. After it, you can write events, kill the process, restart, and read them back. SQLite is a scaffold — Stage 2 throws it away and builds a custom append-only log — but the contract you build *around* SQLite (`openStore`, `persistEvent`, `loadStream`) survives.

## Learning goal

- Use the `sqlite-simple` library to open connections, execute schema DDL, and run parameterized queries
- Write `ToRow` and `FromRow` instances — the bridge between Haskell records and SQL rows
- Design a sensible schema for an event store
- Understand the boundary between *pure model* and *persisted state* — and why keeping them separate matters

## Delivery goal

1. Add `sqlite-simple` to the library's `build-depends`.
2. Create `src/Archivist/Storage/SQLite.hs` exposing:
    - `openStore     :: FilePath -> IO Connection` — opens the DB file and creates the schema if missing
    - `persistUnsignedEvent :: Connection -> String -> Event String -> Int -> IO ()` — write one unsigned event, with its ordinal position
    - `persistSealedEvent   :: Connection -> String -> SealedEvent String -> Int -> IO ()` — write one sealed event
    - `loadUnsigned :: Connection -> String -> IO (EventStream String Unsigned)`
    - `loadSealed   :: Connection -> String -> IO (EventStream String Sealed)`
3. Tests in `test/Archivist/Storage/SQLiteSpec.hs` that write to a temp DB and verify round-trips.

The functions don't need to be fast or elegant — they need to be **correct** and **honest** (sealing invariants preserved on reload).

---

## Concept warm-up (25 min)

### What `sqlite-simple` gives you

```haskell
import Database.SQLite.Simple

-- A connection
conn <- open "store.db"

-- Execute DDL (no return value)
execute_ conn "CREATE TABLE IF NOT EXISTS people (name TEXT, age INTEGER)"

-- Parameterized insert (Note: Only sqlite-simple's `Only` is needed for single-value rows)
execute conn "INSERT INTO people (name, age) VALUES (?, ?)" ("Khalifa" :: String, 30 :: Int)

-- Query
people <- query_ conn "SELECT name, age FROM people" :: IO [(String, Int)]

close conn
```

`?` placeholders prevent SQL injection — never interpolate values into the query string. Always parameterize.

### `ToRow` and `FromRow`

`sqlite-simple` lets you serialize **a tuple** to a row and parse **a tuple** from a row using `ToRow`/`FromRow`. For records, you implement the instances explicitly:

```haskell
data Event = Event { payload, eventId, timestamp :: String }

instance ToRow Event where
  toRow e = toRow (payload e, eventId e, timestamp e)

instance FromRow Event where
  fromRow = Event <$> field <*> field <*> field
```

`field` reads one column. `<$>` and `<*>` plumb them into the constructor in declaration order. (You'll meet these properly in a future *Functor/Applicative* deep-dive if you go beyond Stage 1.)

### Schema design for an event store

Two reasonable approaches:

- **Single table for all events.** A `stream_id` column tags which stream each event belongs to. Filter on it for reads. Simple and fast for SQLite.
- **One table per stream.** Cleaner per-stream queries; messy operations (listing all streams, cross-stream queries) require dynamic SQL.

We use single table. Schema:

```sql
CREATE TABLE IF NOT EXISTS events (
  ordinal      INTEGER PRIMARY KEY AUTOINCREMENT,
  stream_id    TEXT    NOT NULL,
  seal_status  TEXT    NOT NULL,           -- 'unsigned' | 'sealed'
  event_id     TEXT    NOT NULL,
  payload      TEXT    NOT NULL,
  timestamp    TEXT    NOT NULL,
  sealed_hash  TEXT,                       -- NULL for unsigned events
  prev_hash    TEXT,                       -- NULL for unsigned events
  position     INTEGER NOT NULL            -- 0-based ordering within a stream
);

CREATE INDEX IF NOT EXISTS idx_stream_position
  ON events (stream_id, position);
```

- `ordinal` is the insertion order *across all streams*. Useful as a primary key and as a tie-breaker.
- `position` is the 0-based index within a single stream. This is the canonical "what order did these happen?" column.
- `seal_status` lets unsigned and sealed events coexist in the same table.
- Hash columns are `NULL` for unsigned events. The type system in your Haskell code prevents you from mixing them up; the schema is just a convenient bag of bytes.

For Stage 1 we accept a flat single-table schema. Stage 2 throws it away.

### Testing with a temp DB

```haskell
import System.IO.Temp (withSystemTempFile)
import System.IO (hClose)

withSystemTempFile "archivist-test.db" $ \path h -> do
  hClose h         -- we just want the path
  conn <- openStore path
  -- ... write, read, assert ...
  close conn
```

`withSystemTempFile` creates a unique file in `/tmp`, gives you its path, and deletes it when the action returns. Perfect for hermetic database tests.

---

## Read the tests first

Create `test/Archivist/Storage/SQLiteSpec.hs`:

```haskell
module Archivist.Storage.SQLiteSpec (spec) where

import Test.Hspec
import System.IO (hClose)
import System.IO.Temp (withSystemTempFile)
import Database.SQLite.Simple (close)

import Archivist.Event
import Archivist.Stream
import Archivist.Storage.SQLite

spec :: Spec
spec = describe "Archivist.Storage.SQLite" $ do
  let e1 = mkEvent "p1" "evt-1" "t1" :: Event String
      e2 = mkEvent "p2" "evt-2" "t2"
      e3 = mkEvent "p3" "evt-3" "t3"

  it "round-trips an unsigned stream (write then read)" $
    withTempStore $ \conn -> do
      mapM_ (\(pos, e) -> persistUnsignedEvent conn "orders" e pos)
            (zip [0..] [e1, e2, e3])
      s <- loadUnsigned conn "orders"
      eventCount s `shouldBe` 3
      streamId s `shouldBe` "orders"
      map eventId (unsignedEvents s) `shouldBe` ["evt-1", "evt-2", "evt-3"]

  it "round-trips a sealed stream and verify still passes" $
    withTempStore $ \conn -> do
      let unsigned = appendUnsigned e3
                   . appendUnsigned e2
                   . appendUnsigned e1
                   $ emptyUnsigned "orders"
          sealed   = sealStream unsigned
      mapM_ (\(pos, se) -> persistSealedEvent conn "orders" se pos)
            (zip [0..] (sealedEvents sealed))
      loaded <- loadSealed conn "orders"
      eventCount loaded `shouldBe` 3
      verify loaded `shouldBe` True

  it "keeps streams isolated by stream_id" $
    withTempStore $ \conn -> do
      persistUnsignedEvent conn "stream-a" e1 0
      persistUnsignedEvent conn "stream-b" e2 0
      a <- loadUnsigned conn "stream-a"
      b <- loadUnsigned conn "stream-b"
      eventCount a `shouldBe` 1
      eventCount b `shouldBe` 1
      map eventId (unsignedEvents a) `shouldBe` ["evt-1"]
      map eventId (unsignedEvents b) `shouldBe` ["evt-2"]

  it "loadUnsigned on a missing stream returns an empty stream" $
    withTempStore $ \conn -> do
      s <- loadUnsigned conn "does-not-exist"
      eventCount s `shouldBe` 0

withTempStore :: (Database.SQLite.Simple.Connection -> IO a) -> IO a
withTempStore action =
  withSystemTempFile "archivist.db" $ \path h -> do
    hClose h
    conn <- openStore path
    r <- action conn
    close conn
    pure r
```

You'll need to add `temporary` to the test-suite `build-depends`. Add `Archivist.Storage.SQLiteSpec` to `other-modules`.

---

## Build it

### `Archivist.Storage.SQLite`

Create `src/Archivist/Storage/SQLite.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Archivist.Storage.SQLite
  ( openStore
  , persistUnsignedEvent
  , persistSealedEvent
  , loadUnsigned
  , loadSealed
  ) where

import Database.SQLite.Simple
import Archivist.Event
import Archivist.Stream
import Archivist.Hash (Hash)

openStore :: FilePath -> IO Connection
openStore path = do
  conn <- open path
  execute_ conn
    "CREATE TABLE IF NOT EXISTS events (\
    \  ordinal     INTEGER PRIMARY KEY AUTOINCREMENT, \
    \  stream_id   TEXT NOT NULL, \
    \  seal_status TEXT NOT NULL, \
    \  event_id    TEXT NOT NULL, \
    \  payload     TEXT NOT NULL, \
    \  timestamp   TEXT NOT NULL, \
    \  sealed_hash TEXT, \
    \  prev_hash   TEXT, \
    \  position    INTEGER NOT NULL)"
  execute_ conn
    "CREATE INDEX IF NOT EXISTS idx_stream_position ON events (stream_id, position)"
  pure conn

persistUnsignedEvent :: Connection -> String -> Event String -> Int -> IO ()
persistUnsignedEvent conn sid e pos =
  execute conn
    "INSERT INTO events (stream_id, seal_status, event_id, payload, timestamp, \
    \                   sealed_hash, prev_hash, position) \
    \VALUES (?, 'unsigned', ?, ?, ?, NULL, NULL, ?)"
    (sid, eventId e, payload e, timestamp e, pos)

persistSealedEvent :: Connection -> String -> SealedEvent String -> Int -> IO ()
persistSealedEvent conn sid se pos =
  let e = sealedEvent se
  in execute conn
    "INSERT INTO events (stream_id, seal_status, event_id, payload, timestamp, \
    \                   sealed_hash, prev_hash, position) \
    \VALUES (?, 'sealed', ?, ?, ?, ?, ?, ?)"
    (sid, eventId e, payload e, timestamp e,
     sealedHash se, prevHash se, pos)

loadUnsigned :: Connection -> String -> IO (EventStream String Unsigned)
loadUnsigned conn sid = do
  rows <- query conn
    "SELECT payload, event_id, timestamp FROM events \
    \WHERE stream_id = ? AND seal_status = 'unsigned' \
    \ORDER BY position ASC"
    (Only sid) :: IO [(String, String, String)]
  let events = map (\(p, i, t) -> mkEvent p i t) rows
      s0 = emptyUnsigned sid
  pure $ foldl (flip appendUnsigned) s0 events

loadSealed :: Connection -> String -> IO (EventStream String Sealed)
loadSealed conn sid = do
  rows <- query conn
    "SELECT payload, event_id, timestamp, sealed_hash, prev_hash \
    \FROM events WHERE stream_id = ? AND seal_status = 'sealed' \
    \ORDER BY position ASC"
    (Only sid) :: IO [(String, String, String, Hash, Hash)]
  -- Direct construct via the SealedStream constructor.
  -- Requires the constructor to be exported (Option A from L10).
  let toSE (p, i, t, sh, ph) =
        SealedEvent
          { sealedEvent = mkEvent p i t
          , sealedHash  = sh
          , prevHash    = ph
          }
  pure $ SealedStream sid (map toSE rows)
```

We reuse `appendUnsigned` on the unsigned-load path (clean), but for sealed streams we *don't* call `sealStream` on reload — the hashes are already in the DB. We construct `SealedStream` directly. This means **`verify` is the post-load check** — if anything got corrupted in transit, `verify` catches it.

### Update the cabal file

Library `build-depends:`:

```cabal
                    , sqlite-simple ^>=0.4
```

Test-suite `build-depends:`:

```cabal
                    , sqlite-simple ^>=0.4
                    , temporary ^>=1.3
```

Also: add `Archivist.Storage.SQLite` to the library's `exposed-modules`.

---

## Verify

```sh
runghc check.hs
```

Bonus: poke at your test DB by hand. Drop a `traceIO ("DB path: " ++ path)` into one of the tests, copy the path before deletion, then `sqlite3 /path/to/file.db` and `SELECT * FROM events;`. Seeing your events as SQL rows is satisfying.

---

## Design choices baked into this lesson

- **Single-table schema** with `stream_id` and `seal_status` columns — simple, indexable, easy to query. The alternative (table-per-stream) requires dynamic SQL. Single-table wins in Stage 1.
- **`position INTEGER` for stream-local order** — separate from the auto-increment `ordinal`. `ordinal` orders inserts globally; `position` orders events within their stream. Both serve a purpose; both are useful for debugging.
- **Hashes stored as `TEXT` (hex)** — matches the `Hash = String` choice from L10. Could be `BLOB` (raw bytes) for half the storage; we picked text for `sqlite3` CLI debugging convenience.
- **Caller passes the `position` explicitly** — alternative: have `persist*Event` query the current max position and increment. Simpler and racier; we leave that decision to the caller (this becomes important in Stage 2 where ordering is more carefully managed).
- **Two separate functions per seal status** — `persistUnsignedEvent` and `persistSealedEvent` instead of one. Cleaner with the GADT; an existential `SomeStream e` would unify them but adds heaviness. Saved for Stretch.
- **Sealed streams are reconstructed by *direct construction*, not `sealStream`** — because the hashes are *already* in the DB. Re-running `sealStream` would *recompute* the chain over plain events and ignore the stored hashes, defeating the point. `verify` after load is your safety net.
- **`SealedStream` constructor must be exported** for `loadSealed` to construct one — same trade as L10. The clean alternative remains `Archivist.Stream.Internal`.
- **No transactions, no batching** — every `INSERT` is its own commit. Fine for a learning exercise; production would wrap a batch in `withTransaction`.
- **`OverloadedStrings` pragma** — `sqlite-simple` queries are typed `Query`, and `OverloadedStrings` lets you write them as plain string literals. Industry standard.

---

## Self-check

1. Why does the schema have *both* `ordinal` and `position`? Could you drop one?
2. Why doesn't `loadSealed` call `sealStream` on the reconstructed events?
3. What would go wrong if you parameterized SQL queries with string concatenation instead of `?`? Give a concrete attack.
4. Why is `withSystemTempFile` better for tests than just opening `"./test.db"`?
5. After your tests pass, can you list every *invariant* your storage layer preserves between write and read? (Order, hash values, seal status, stream isolation, …)

---

## Stretch

- Add `listStreams :: Connection -> IO [String]` returning all distinct `stream_id`s. Trivial query, useful demo for L13.
- Wrap a bulk insert in `withTransaction` and measure the speedup with `criterion` or just `Data.Time.getCurrentTime`. Real numbers ground the lesson.
- Define an existential wrapper:
  ```haskell
  data SomeEventStream e where
    SomeEventStream :: EventStream e s -> SomeEventStream e
  ```
  And `loadStream :: Connection -> String -> IO (SomeEventStream String)` that picks `Unsigned` or `Sealed` based on the `seal_status` of the first row. The caller pattern-matches.
- Add a `migrations` concept: store a `schema_version` row and a list of DDL migrations to apply at startup. Pretend you're running this in production a year from now.

---

## Done?

`cabal test` is green → **move on to [Lesson 12](../12-quickcheck/README.md).**
