# Lesson 9 — GADTs: making illegal states unrepresentable

## Where you are

You shipped phantom-typed seal status in Lesson 8. The compiler refuses `appendUnsigned` on a sealed stream, and refuses `verify` on an unsigned one. The type system is doing real work for you.

But there's a quiet weakness. With the phantom approach, both `Stream e Unsigned` and `Stream e Sealed` use *the same data constructor* — they store the same shape. The distinction lives entirely in the *type tag*. That works for our current needs, but it doesn't let the two cases **carry different data**.

In the project's real design, sealed streams hold `SealedEvent`s (event + hash + previous-hash) while unsigned streams hold plain `Event`s. The runtime *shape* differs. Phantom types can't express that.

**GADTs (Generalized ADTs) can.** This is the lesson where you replace the phantom approach with the real thing — and where Haskell's type system stops feeling like documentation and starts feeling like a proof assistant.

## Learning goal

- Understand what GADTs add over regular ADTs: **constructor-specific return types**
- Read the GADT syntax — it looks different from regular `data` declarations
- See how GADTs make `appendUnsigned`/`verify` checks happen *because of the data, not in spite of it*
- Add the placeholder `SealedEvent` type so Lesson 10's hashing has somewhere to live

## Delivery goal

1. Replace `Stream e s` (phantom) with `EventStream e s` (GADT). The unsigned and sealed branches carry different data:
    ```haskell
    data EventStream e s where
      UnsignedStream :: String -> [Event e]       -> EventStream e Unsigned
      SealedStream   :: String -> [SealedEvent e] -> EventStream e Sealed
    ```
2. Introduce `SealedEvent e` as a placeholder — same shape as a future cryptographically-sealed event, but `hash` and `prevHash` are plain `String`s for now. Real hashing arrives in Lesson 10.
3. Re-implement all stream operations against the GADT:
    - `emptyUnsigned`, `appendUnsigned`, `sealStream`, `verify`, `eventCount`, `replay`, `streamId`, `events`
4. `sealStream` now does *real work*: it converts each `Event e` into a `SealedEvent e`. For this lesson the conversion is trivial (`hash = ""`, `prevHash = ""`). Lesson 10 fills in the cryptography.
5. Keep tests green. Some signatures will need adjustments, particularly anywhere you fetch `events` (which now returns `[Event e]` *or* `[SealedEvent e]` depending on seal status — you'll need accessor variants).

This is the most type-heavy lesson in Stage 1. Expect to wrestle. The reward is permanent: by the end you'll have shipped a real GADT and you'll understand why the Haskell community keeps writing essays about how nice they are.

---

## Concept warm-up (30 min)

### Regular ADTs revisited

A regular `data` declaration looks like:

```haskell
data Maybe a = Nothing | Just a
```

Each constructor returns *the same type*: both `Nothing` and `Just a` give you a `Maybe a`. The type parameter `a` is the same across all constructors.

### GADTs: per-constructor return types

GADT syntax writes each constructor's type signature explicitly:

```haskell
{-# LANGUAGE GADTs #-}

data Expr a where
  IntE  :: Int  -> Expr Int
  BoolE :: Bool -> Expr Bool
  AddE  :: Expr Int -> Expr Int -> Expr Int
  IfE   :: Expr Bool -> Expr a -> Expr a -> Expr a
```

Read each line: "this constructor takes these arguments and returns a value of type `Expr <something specific>`."

Notice:
- `IntE` returns `Expr Int` — *specifically*. Not `Expr a` for any `a`.
- `BoolE` returns `Expr Bool` — also specific.
- `AddE` takes two `Expr Int` and returns `Expr Int`.

This is the new power: **the constructor decides the type parameter**. An `Expr Bool` value can only have come from a `BoolE` or an `IfE`. The compiler *knows* this.

The evaluator becomes magical:

```haskell
eval :: Expr a -> a
eval (IntE n)         = n              -- here `a` is Int
eval (BoolE b)        = b              -- here `a` is Bool
eval (AddE x y)       = eval x + eval y
eval (IfE c t e)      = if eval c then eval t else eval e
```

Each branch operates in a *different* type, and the compiler keeps track. `eval (AddE (BoolE True) (IntE 5))` won't even compile.

This is "making illegal states unrepresentable" — the slogan you'll hear forever in Haskell circles. It's what the doc in `project_context.md` promises about `verify`:

> verify type-checks only on Sealed streams, calling it on Unsigned is a compile error.

You already achieved that with phantoms. With GADTs, you go further: the *internal data* of a sealed stream and an unsigned stream is different, and the compiler enforces it.

### Pattern matching teaches the compiler

When you pattern-match on a GADT constructor, the compiler **refines** what it knows about the type variables. Inside the `UnsignedStream` branch of a pattern match, the compiler knows `s ~ Unsigned`. Inside the `SealedStream` branch, it knows `s ~ Sealed`. This refinement is why GADT pattern matching feels so satisfying — every branch operates in a more specific type than the outer signature.

### The cost: a few language extensions, a few deriving losses

GADTs need:

```haskell
{-# LANGUAGE GADTs #-}
```

…and often:

```haskell
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleContexts   #-}
```

`deriving (Show, Eq)` *on the data declaration line* doesn't work for GADTs. Instead you write standalone declarations:

```haskell
deriving instance Show e => Show (EventStream e s)
deriving instance Eq   e => Eq   (EventStream e s)
```

It's annoying the first time. Then it's normal.

---

## Read the tests first

Update `test/Archivist/SealSpec.hs` to use the GADT names and check the new structure:

```haskell
module Archivist.SealSpec (spec) where

import Test.Hspec
import Archivist.Event
import Archivist.Stream

spec :: Spec
spec = describe "EventStream (GADT seal status)" $ do
  let e1 = mkEvent "p1" "evt-1" "t1" :: Event String
      e2 = mkEvent "p2" "evt-2" "t2" :: Event String

  it "appendUnsigned grows the stream and keeps it Unsigned" $ do
    let s = appendUnsigned e2 (appendUnsigned e1 (emptyUnsigned "orders"))
    eventCount s `shouldBe` 2
    streamId s `shouldBe` "orders"

  it "sealStream converts each Event into a SealedEvent (placeholder hashes for now)" $ do
    let u  = appendUnsigned e1 (emptyUnsigned "orders")
        s  = sealStream u
    eventCount s `shouldBe` 1

  it "sealedEvents on a SealedStream exposes the SealedEvent list" $ do
    let s = sealStream (appendUnsigned e1 (emptyUnsigned "x"))
    length (sealedEvents s) `shouldBe` 1

  it "verify returns True on a sealed stream (real check arrives in L10)" $
    verify (sealStream (appendUnsigned e1 (emptyUnsigned "x"))) `shouldBe` True

  it "replay works regardless of seal status" $ do
    let u = appendUnsigned e2 (appendUnsigned e1 (emptyUnsigned "x"))
        s = sealStream u
    -- For unsigned: pure events
    replay (\acc e -> acc ++ payload e) "" u `shouldBe` "p1p2"
    -- For sealed: SealedEvents — projection acts on the underlying Event
    replay (\acc se -> acc ++ payload (sealedEvent se)) "" s `shouldBe` "p1"
```

The new function names you'll need to expose:

- `sealedEvents :: EventStream e Sealed -> [SealedEvent e]`
- `sealedEvent  :: SealedEvent e        -> Event e` (field accessor)

Replay's seed-and-step types differ depending on whether the stream is unsigned or sealed — that's the GADT shining through. We supply two separate `replay`s in the build below to keep types unambiguous.

---

## Build it

### The new `Archivist.Stream`

Rewrite `src/Archivist/Stream.hs`:

```haskell
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleContexts   #-}

module Archivist.Stream
  ( -- types
    EventStream
  , SealedEvent (..)
  , Sealed
  , Unsigned
    -- constructors / smart builders
  , emptyUnsigned
  , appendUnsigned
  , sealStream
    -- queries
  , streamId
  , unsignedEvents
  , sealedEvents
  , eventCount
  , verify
    -- folds
  , replayUnsigned
  , replaySealed
    -- re-exports
  , module Archivist.Event
  ) where

import Data.List (foldl')
import Archivist.Event

-- Phantom-style tags still useful as type-level labels
data Sealed
data Unsigned

-- A sealed event carries placeholder hashes for now.
-- Lesson 10 replaces these with real cryptographic digests.
data SealedEvent e = SealedEvent
  { sealedEvent :: Event e
  , sealedHash  :: String
  , prevHash    :: String
  }

deriving instance Eq   e => Eq   (SealedEvent e)
deriving instance Show e => Show (SealedEvent e)

-- The GADT itself
data EventStream e s where
  UnsignedStream :: String -> [Event e]       -> EventStream e Unsigned
  SealedStream   :: String -> [SealedEvent e] -> EventStream e Sealed

deriving instance Show e => Show (EventStream e s)
deriving instance Eq   e => Eq   (EventStream e s)

-- Queries
streamId :: EventStream e s -> String
streamId (UnsignedStream sid _) = sid
streamId (SealedStream   sid _) = sid

eventCount :: EventStream e s -> Int
eventCount (UnsignedStream _ es) = length es
eventCount (SealedStream   _ es) = length es

unsignedEvents :: EventStream e Unsigned -> [Event e]
unsignedEvents (UnsignedStream _ es) = es

sealedEvents :: EventStream e Sealed -> [SealedEvent e]
sealedEvents (SealedStream _ es) = es

-- Smart constructors / mutations
emptyUnsigned :: String -> EventStream e Unsigned
emptyUnsigned sid = UnsignedStream sid []

appendUnsigned :: Event e -> EventStream e Unsigned -> EventStream e Unsigned
appendUnsigned e (UnsignedStream sid es) = UnsignedStream sid (es ++ [e])

-- Sealing: convert each Event to a SealedEvent with placeholder hashes.
-- Real cryptography in Lesson 10.
sealStream :: EventStream e Unsigned -> EventStream e Sealed
sealStream (UnsignedStream sid es) = SealedStream sid (map toSealed es)
  where
    toSealed e = SealedEvent { sealedEvent = e, sealedHash = "", prevHash = "" }

-- Verify: structural placeholder. Real check coming.
verify :: EventStream e Sealed -> Bool
verify _ = True

-- Folds (one per seal status, because the element type differs)
replayUnsigned :: (a -> Event e -> a) -> a -> EventStream e Unsigned -> a
replayUnsigned step seed (UnsignedStream _ es) = foldl' step seed es

replaySealed :: (a -> SealedEvent e -> a) -> a -> EventStream e Sealed -> a
replaySealed step seed (SealedStream _ es) = foldl' step seed es
```

A single polymorphic `replay` is awkward here because the element type depends on the seal status. Two functions, one per branch, is cleaner. (You can unify them later with a type family if you want — Stretch.)

The exported `replay` from the test file will need to become `replayUnsigned` or `replaySealed`. Update accordingly.

### Update `Archivist.Projection`

The projections need to choose which variant they support. The minimal change:

```haskell
countEvents   :: EventStream e s        -> Int
countEvents   = eventCount                     -- delegates to the GADT-aware function

latestPayload :: EventStream String Unsigned -> Maybe String
latestPayload = replayUnsigned (\_ e -> Just (payload e)) Nothing

payloadCounts :: EventStream String Unsigned -> [(String, Int)]
payloadCounts = replayUnsigned step []
  where ...
```

`countEvents` keeps working for any seal status. `latestPayload` and `payloadCounts` are projections over event payloads, so we keep them on unsigned streams. Adding sealed counterparts is a Stretch exercise.

### Update existing tests

Every place that used `Stream` now uses `EventStream`. Every `replay` becomes `replayUnsigned` (in the tests we have). Walk the compiler errors top to bottom — they'll lead you.

### The pay-off — try a deliberate compile error

In a scratch file or temporarily in `Main.hs`, paste this:

```haskell
let s = sealStream (emptyUnsigned "x") :: EventStream String Sealed
in appendUnsigned (mkEvent "p" "i" "t") s
```

Run `cabal build`. Read the error. The compiler refuses because `appendUnsigned`'s second argument must be `EventStream e Unsigned`, and you handed it `EventStream String Sealed`. This was already true with phantoms; the GADT just makes the *underlying data* enforce it, not just a tag.

---

## Verify

```sh
runghc check.hs
```

When this is green, **Act II is complete.** You have, in working Haskell code, the type-level guarantee that:

- You can append only to unsigned streams.
- You can verify only sealed streams.
- An unsigned stream literally cannot hold sealed events, and vice versa.

That's the property the project context document promised. It's now a compile-time fact.

---

## Self-check

1. What does a GADT add over a regular ADT?
2. Inside a pattern match `case s of UnsignedStream _ _ -> ...`, what does the compiler know about the type parameter `s` of `s`?
3. Why does `deriving (Show, Eq)` after the GADT declaration not work, while standalone `deriving instance ...` does?
4. We split `replay` into `replayUnsigned` and `replaySealed`. Why couldn't one polymorphic `replay` work cleanly?
5. The doc's design includes a `LegacyEvent` for streams that get upgraded from unsigned to sealed mid-life. How would you add it to the GADT? Sketch a third constructor that holds *a mix* of legacy events and sealed events. (You don't need to implement it yet.)

---

## Stretch

- Add a third constructor `MixedSealedStream :: String -> [Either (Event e) (SealedEvent e)] -> EventStream e Sealed` representing a stream that was once unsigned and got upgraded — `Left` for legacy events, `Right` for newly sealed ones. Update `verify` to verify only the `Right` portion.
- Use a **type family** to unify `replayUnsigned` and `replaySealed`:
  ```haskell
  {-# LANGUAGE TypeFamilies #-}
  type family ElementOf s e where
    ElementOf Unsigned e = Event e
    ElementOf Sealed   e = SealedEvent e

  replay :: (a -> ElementOf s e -> a) -> a -> EventStream e s -> a
  ```
  Implementing this is non-trivial — it requires pattern-matching on the GADT to refine `s`. Worth attempting only if you're enjoying yourself.
- Read `:i GADTs` in GHCi — it just shows you the extension docs, but follow the link if curious. Sandy Maguire's *Thinking with Types* book and Edward Kmett's many blog posts are where this rabbit hole leads.

---

## Design choices baked into this lesson

- **Name change `Stream` → `EventStream`** — the project context document uses both names somewhat interchangeably. I gave the GADT version the `EventStream` name because its shape is meaningfully different from L8's. If you'd rather keep `Stream`, do — it's just a rename.
- **Two separate `replay` functions (`replayUnsigned`, `replaySealed`)** — element types differ per GADT branch, so a single polymorphic `replay` requires a type family (in the Stretch). Two functions is honest and beginner-friendly. Unify later if you reach for it.
- **`unsignedEvents` / `sealedEvents` accessors** — needed because GADT field selectors don't elegantly compose across branches. Some teams use lenses or prisms here; we don't, in Stage 1.
- **`SealedEvent` hash fields are `String`** — placeholder. L10 swaps them for either `ByteString` (raw bytes) or hex-encoded `String`. Pick once in L10 and stick with it.
- **`MixedSealedStream` for legacy events isn't in the main GADT** — the project context mentions `UnsignedLegacy` markers when a stream upgrades from `Unsigned` to `Sealed`. Adding the constructor is straightforward; I left it as a Stretch because the upgrade path is a side quest from the main type-safety story.
- **`countEvents` works for any seal status; `latestPayload` / `payloadCounts` are unsigned-only** — projections that touch payload semantics specialize; projections that just count don't. You can add sealed-side variants when you need them.
- **No real `verify` yet** — same placeholder as L8. L10 is where this gets honest.

---

## Done?

`cabal test` is green → **Act II complete.**

You've shipped: validation with `Maybe`/`Either`, a custom typeclass, projections built on folds, phantom types, and now a GADT that makes the seal-status guarantees structural rather than tagged. The type system is now doing meaningful work for you.

Tell Claude when you're ready, and we'll write **Run 3 (Act III — *It survives a crash*)**: real cryptographic hashing, SQLite persistence, QuickCheck properties, and the capstone.
