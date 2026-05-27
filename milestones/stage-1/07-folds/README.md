# Lesson 7 — Folds: where event sourcing becomes obvious

## Where you are

You have a typed event store, validation, custom `Show`, and a tiny typeclass. Two more lessons until the GADT showpiece.

This lesson is the **conceptual heart** of event sourcing. Every textbook explanation of event sourcing eventually says: *"the current state is a function of all past events."* That function, in Haskell, is literally `foldl`.

## Learning goal

- Recognize the **fold** pattern as the dual of recursion
- Distinguish `foldr`, `foldl`, and `foldl'` — know when to reach for which
- Understand strictness in passing (you'll hit it for real in Stage 2)
- Write **`replay`** — the operation that takes a stream and an initial state, runs every event through a reducer, and produces the current state
- Build a **projection** — your first read model

## Delivery goal

1. Add `Archivist.Stream.replay :: (s -> Event -> s) -> s -> Stream -> s` — a left fold over the events in a stream.
2. Create `src/Archivist/Projection.hs` with **three** example projections built on top of `replay`:
    - `countEvents :: Stream -> Int`
    - `latestPayload :: Stream -> Maybe String`
    - `payloadCounts :: Stream -> [(String, Int)]` — list of `(payload, occurrences)`, in **insertion order** of first occurrence
3. Add `Archivist.Projection` to the library's `exposed-modules` and write `test/Archivist/ProjectionSpec.hs`.

---

## Concept warm-up (25 min)

### Recursion → fold

Imagine summing a list. The recursive shape:

```haskell
mySum :: [Int] -> Int
mySum []     = 0
mySum (x:xs) = x + mySum xs
```

The recursive shape for length:

```haskell
myLength :: [a] -> Int
myLength []     = 0
myLength (_:xs) = 1 + myLength xs
```

They look almost the same. The only differences are:

1. The starting value (`0`)
2. The combiner (`x +`, vs `1 +`)

That pattern is so universal it has a name: **fold**. `foldr` is the right-associative version, `foldl` is left-associative.

```haskell
:t foldr
-- foldr :: Foldable t => (a -> b -> b) -> b -> t a -> b

foldr (+) 0 [1,2,3,4]      -- 10
foldr (:) [] [1,2,3]       -- [1,2,3]    -- (Yes, that's how you "copy" a list.)

:t foldl
-- foldl :: Foldable t => (b -> a -> b) -> b -> t a -> b

foldl (+) 0 [1,2,3,4]      -- 10
foldl (\acc x -> acc ++ [x]) [] [1,2,3]   -- [1,2,3]  (slow, but illustrative)
```

The shape of `foldr`: `foldr f z [x1, x2, x3] = f x1 (f x2 (f x3 z))` — combines right-to-left.

The shape of `foldl`: `foldl f z [x1, x2, x3] = f (f (f z x1) x2) x3` — combines left-to-right.

For event sourcing we want **left-to-right** ("replay events in order, accumulating state"). That's `foldl`.

### `foldl` vs `foldl'` — the strictness gotcha

Haskell is lazy. `foldl` builds up a giant unevaluated expression `f (f (f (f z x1) x2) x3) x4 ...` and only collapses it at the end. For long streams this can blow the stack.

`Data.List.foldl'` is the **strict** version: it evaluates the accumulator at each step. Use it for any fold over a list you actually want to *compute*.

```haskell
import Data.List (foldl')

foldl' (+) 0 [1..1000000]    -- fast, constant memory
foldl  (+) 0 [1..1000000]    -- might blow the stack
```

**Rule of thumb:** if your fold is accumulating a strict value (a number, a record, a `Map`), use `foldl'`. If it's accumulating a lazy data structure you might stream out, `foldr` or plain `foldl` are fine.

For Archivist, **always use `foldl'` for state replay.** Treat it as the default.

### Folds and event sourcing

Project context, in the doc, says:

> Events are immutable facts... the fold that reconstructs state handles both event shapes.

Here's the shape of that fold:

```haskell
replay :: (s -> Event -> s) -> s -> Stream -> s
replay step initialState stream = foldl' step initialState (events stream)
```

That's it. Event sourcing's "magic" is one function. Different `step` functions give different views of the same underlying stream — that's a **projection**.

### Projections — read models built from a fold

A projection answers a specific question about the stream:

```haskell
-- "How many events are in the stream?"
countEvents :: Stream -> Int
countEvents = replay (\count _ -> count + 1) 0

-- "What was the most recent payload?"
latestPayload :: Stream -> Maybe String
latestPayload = replay (\_ e -> Just (payload e)) Nothing
-- Note: each new event replaces the previous "answer" — the fold ends on the latest.
```

The same stream can serve unlimited projections. Each is a separate fold. This is the read-side of CQRS, in five lines.

---

## Read the tests first

Add to `test/Archivist/StreamSpec.hs`:

```haskell
  describe "replay" $ do
    let e1 = mkEvent "p1" "evt-1" "t1"
        e2 = mkEvent "p2" "evt-2" "t2"
        s  = appendToStream e2 (appendToStream e1 (emptyStream "x"))

    it "is identity when the step is `\\acc _ -> acc`" $
      replay (\acc _ -> acc) "init" s `shouldBe` "init"

    it "applies the step in oldest-first order" $
      replay (\acc e -> acc ++ "|" ++ payload e) "" s `shouldBe` "|p1|p2"

    it "returns the seed for an empty stream" $
      replay (\acc _ -> acc + (1 :: Int)) 7 (emptyStream "x") `shouldBe` 7
```

Create `test/Archivist/ProjectionSpec.hs`:

```haskell
module Archivist.ProjectionSpec (spec) where

import Test.Hspec
import Archivist.Event
import Archivist.Stream
import Archivist.Projection

spec :: Spec
spec = do
  let e1 = mkEvent "order"   "evt-1" "t1"
      e2 = mkEvent "payment" "evt-2" "t2"
      e3 = mkEvent "order"   "evt-3" "t3"
      s  = foldr appendToStream (emptyStream "shop") [e3, e2, e1]
           -- ^ note: foldr+cons-style append gives oldest-first since
           --   appendToStream itself appends to the end.

  describe "countEvents" $ do
    it "is 0 for an empty stream" $ countEvents (emptyStream "x") `shouldBe` 0
    it "counts each event"        $ countEvents s `shouldBe` 3

  describe "latestPayload" $ do
    it "is Nothing for an empty stream"     $ latestPayload (emptyStream "x") `shouldBe` Nothing
    it "is the payload of the newest event" $ latestPayload s `shouldBe` Just "order"

  describe "payloadCounts" $ do
    it "tracks counts and preserves first-seen order" $
      payloadCounts s `shouldBe` [("order", 2), ("payment", 1)]

    it "is empty for an empty stream" $
      payloadCounts (emptyStream "x") `shouldBe` []
```

Add `Archivist.ProjectionSpec` to `other-modules:`.

---

## Build it

### `replay`

In `src/Archivist/Stream.hs`:

```haskell
import Data.List (foldl')

replay :: (s -> Event -> s) -> s -> Stream -> s
replay step seed stream = foldl' step seed (events stream)
```

Add `replay` to the export list.

### `Archivist.Projection`

Create `src/Archivist/Projection.hs`:

```haskell
module Archivist.Projection
  ( countEvents
  , latestPayload
  , payloadCounts
  ) where

import Archivist.Event
import Archivist.Stream

countEvents :: Stream -> Int
countEvents = replay (\acc _ -> acc + 1) 0

latestPayload :: Stream -> Maybe String
latestPayload = replay (\_ e -> Just (payload e)) Nothing

payloadCounts :: Stream -> [(String, Int)]
payloadCounts = replay step []
  where
    step :: [(String, Int)] -> Event -> [(String, Int)]
    step acc e = bump (payload e) acc

    bump :: String -> [(String, Int)] -> [(String, Int)]
    bump p []           = [(p, 1)]
    bump p ((k, n) : rest)
      | k == p          = (k, n + 1) : rest
      | otherwise       = (k, n) : bump p rest
```

A list of pairs is the *least efficient* data structure for this — O(n) per insert. We use it for clarity. In real code you'd reach for `Data.Map.Strict`. Read about it when you're curious.

Register `Archivist.Projection` in `archivist.cabal`'s `exposed-modules`.

---

## Verify

```sh
runghc check.hs
```

---

## Self-check

1. Explain `replay` in one sentence.
2. What's the difference between `foldl` and `foldl'`? Why does it matter?
3. The project context calls projections "read models". Why does it say a single event store can support many of them?
4. Why does `latestPayload` use `Just (payload e)` as the *new* value (ignoring the accumulator)? What does that say about the semantics?
5. If you replaced `foldl'` with `foldr` in `replay`, what would change about the behavior? About the performance?

---

## Stretch

- Write `eventsBefore :: String -> Stream -> [Event]` — every event whose timestamp is strictly less than the given one. Implement it as a `foldl'`.
- Write `splitOnTimestamp :: String -> Stream -> (Stream, Stream)` — return `(before, atOrAfter)`. The streams should both have the same `streamId`. This is a step toward *snapshotting* (Stage 1 doesn't need snapshots yet, but the slot is in your head now).
- Reimplement `payloadCounts` using `Data.Map.Strict` instead of an association list. Compare the diff.
- Read `:i Foldable` in GHCi. `replay` over a `Stream` works because lists are `Foldable`. With a tiny instance, your `Stream` itself could be `Foldable`. (Don't do it yet — phantom types in the next lesson will make it more interesting.)

---

## Design choices baked into this lesson

- **Three specific projections (count / latest / payload counts)** — they're *examples*, not core domain code. Your real projections will be different. Think of `Archivist.Projection` as a sandbox module that gets replaced by real read models later.
- **`payloadCounts` uses an association list** — O(n) per insert. The right tool is `Data.Map.Strict.Map String Int`. I went with the slow version because it makes the fold *transparent* (no library calls hidden in the step). Swap it out the moment you care about performance.
- **`latestPayload :: Stream -> Maybe String` returns the payload only** — defensible to return the whole `Event` instead (`latestEvent :: Stream -> Maybe Event`). Either is fine; the choice depends on whether downstream code wants the metadata.
- **`replay` lives in `Archivist.Stream`, not a new module** — projections live in `Archivist.Projection` because they multiply. `replay` is the *primitive* and belongs with the type it operates on.
- **`foldl'` everywhere, not `foldr`** — deliberate. Event replay accumulates strict state; `foldl'` is the safe default. If you ever want to *stream* projection output lazily, `foldr` becomes interesting again.

---

## Done?

`cabal test` is green → **move on to [Lesson 8](../08-phantom-types/README.md).**
