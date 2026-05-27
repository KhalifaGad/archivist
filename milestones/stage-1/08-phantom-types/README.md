# Lesson 8 — Phantom types: using the type system to prevent illegal states

## Where you are

Two lessons remain in Act II. This one sets up the showpiece in Lesson 9.

Until now, types have described **data**: `Event` has these fields, `Stream` holds events. This lesson is the first time we use the type system to describe **constraints** — to make some operations *not even possible to call* on the wrong kind of value.

## Learning goal

- Understand what a **phantom type parameter** is: a type variable that doesn't appear on the right side of `data`
- Use phantoms to *tag* values with a property the compiler tracks
- Use **smart constructors** with an *unexported* data constructor to make phantoms actually safe
- Parameterize `Event` by its payload type — your first taste of polymorphic data

This is the lesson where Haskell starts feeling unlike anything else.

## Delivery goal

Refactor the project so:

1. `Event` is parameterized by payload type: `data Event e = Event { payload :: e, eventId :: String, timestamp :: String }`.
2. `Stream` becomes `Stream e s` — parameterized by **payload type `e`** and **seal status `s`** (a phantom).
3. The data constructors `Event` and `Stream` are **not exported** — callers must go through smart constructors:
    - `mkEvent :: e -> String -> String -> Event e`
    - `emptyUnsigned :: String -> Stream e Unsigned`
    - `emptySealed   :: String -> Stream e Sealed` *(useful for tests; in production the only way to a sealed stream is to seal an unsigned one)*
4. Operations are gated by seal status at the *type* level:
    - `appendUnsigned :: Event e -> Stream e Unsigned -> Stream e Unsigned`
    - `sealStream    :: Stream e Unsigned -> Stream e Sealed`
    - `verify        :: Stream e Sealed   -> Bool` — for now, always returns `True` (real hashing in Lesson 10)
5. Trying to call `appendUnsigned` on a `Stream e Sealed` is a **compile error**. Trying to call `verify` on a `Stream e Unsigned` is a **compile error**.

Existing projections (`countEvents`, `latestPayload`, `payloadCounts`) work on any seal status. You'll need to update their signatures.

This is a meaningful refactor. Take your time. The tests will guide you.

---

## Concept warm-up (30 min)

### A type parameter that *isn't used*

Look at this declaration:

```haskell
data Tagged tag a = Tagged a
```

`tag` appears on the left of `=` but **not** on the right. It's never stored. It's a **phantom** — a piece of *type-level information* that disappears at runtime.

```haskell
data Sealed
data Unsigned

-- These two values look identical at runtime, but have different types:
let a = Tagged 42 :: Tagged Sealed Int
let b = Tagged 42 :: Tagged Unsigned Int
:t a    -- Tagged Sealed Int
:t b    -- Tagged Unsigned Int

-- The compiler will refuse to mix them up:
let combine :: Tagged Sealed Int -> Tagged Sealed Int -> Tagged Sealed Int
    combine (Tagged x) (Tagged y) = Tagged (x + y)

combine a a     -- OK
combine a b     -- compile error: types don't match
```

`Sealed` and `Unsigned` here are just **uninhabited types** — they have no values, no constructors. We only use their *names* as type-level tags.

### Why a phantom alone isn't enough — smart constructors

A phantom only enforces a property if users can't fabricate values that lie. If the constructor is exported, anyone can write `Tagged 42 :: Tagged Sealed Int` and bypass your safety:

```haskell
-- Even if your "rule" is "only sealStream produces a Sealed-tagged thing,"
-- this is still legal as long as the constructor is exported:
let cheating = Tagged 42 :: Tagged Sealed Int
```

The fix: **don't export the constructor.** Export the *type* and provide *smart constructors* that bake the property in.

```haskell
module Tagged
  ( Tagged           -- type only, NO (..)
  , mkUnsigned       -- :: a -> Tagged Unsigned a
  , seal             -- :: Tagged Unsigned a -> Tagged Sealed a
  ) where

data Tagged tag a = Tagged a   -- constructor stays private

mkUnsigned :: a -> Tagged Unsigned a
mkUnsigned = Tagged

seal :: Tagged Unsigned a -> Tagged Sealed a
seal (Tagged x) = Tagged x       -- same value, different *type*
```

Outside the module, the only way to get a `Tagged Sealed a` is to call `seal` on a `Tagged Unsigned a`. The type system now enforces the **invariant** that sealing happened.

This pattern is everywhere in real Haskell — `Data.Text`, `Data.ByteString`, `Network.URI` all use it.

### Parameterizing `Event` by payload type

So far, `payload` has been `String`. That was a teaching simplification. Real event sourcing wants an `Event` to carry a *typed* payload:

```haskell
data Event e = Event
  { payload   :: e
  , eventId   :: String
  , timestamp :: String
  } deriving (Eq, Ord)

-- Now mkEvent is polymorphic in payload type:
:t mkEvent
-- mkEvent :: e -> String -> String -> Event e

mkEvent "shipped"        "evt-1" "t1"   :: Event String
mkEvent (42 :: Int)      "evt-2" "t2"   :: Event Int
```

You can put any payload type you like — `String`, a custom record, an ADT representing the event types in a domain. The store doesn't care; it stores what you give it.

The custom `Show` instance from Lesson 6 now needs `Show e =>`:

```haskell
instance Show e => Show (Event e) where
  show e = "<" ++ eventId e ++ " @ " ++ timestamp e ++ ": " ++ show (payload e) ++ ">"
```

That constraint reads: "we can show an `Event e` if we can show its payload."

---

## Read the tests first

Rewrite `test/Archivist/EventSpec.hs` and `test/Archivist/StreamSpec.hs` to use the new parameterized types. Add `test/Archivist/SealSpec.hs`:

```haskell
module Archivist.SealSpec (spec) where

import Test.Hspec
import Archivist.Event
import Archivist.Stream

spec :: Spec
spec = describe "Seal status" $ do
  let e1 = mkEvent "p1" "evt-1" "t1" :: Event String
      e2 = mkEvent "p2" "evt-2" "t2" :: Event String

  it "can build an Unsigned stream and append to it" $ do
    let s = appendUnsigned e2 (appendUnsigned e1 (emptyUnsigned "orders"))
    eventCount s `shouldBe` 2

  it "can seal an Unsigned stream into a Sealed one" $ do
    let u = appendUnsigned e1 (emptyUnsigned "orders") :: Stream String Unsigned
        s = sealStream u                                :: Stream String Sealed
    eventCount s `shouldBe` 1     -- contents preserved

  it "verify works on a Sealed stream" $ do
    let s = sealStream (appendUnsigned e1 (emptyUnsigned "orders"))
    verify s `shouldBe` True

  it "supports projections on either seal status" $ do
    let u = appendUnsigned e1 (emptyUnsigned "x")
        s = sealStream u
    countEvents u `shouldBe` 1
    countEvents s `shouldBe` 1
```

And — this is important — add a **non-runnable test file** documenting the compile errors. It lives outside the test suite. Create `test/Archivist/SealCompileErrors.txt` (or comment-block inside the SealSpec) listing:

```text
-- These lines should each FAIL TO COMPILE if you uncomment them.
-- Try it locally to verify the type system is doing its job:

--   let u = emptyUnsigned "x" :: Stream String Unsigned
--   let s = sealStream u
--   appendUnsigned (mkEvent "p" "i" "t") s        -- error: expected Unsigned, got Sealed
--   verify u                                       -- error: expected Sealed, got Unsigned
```

Hspec can't run a "this fails to compile" assertion — but uncomment the lines in your editor whenever you want to *see* the type system at work. That experience is the whole point of this lesson.

Update `archivist.cabal`'s `other-modules` to include `Archivist.SealSpec`.

---

## Build it

### Module surface

Rewrite `src/Archivist/Event.hs`:

```haskell
{-# LANGUAGE FlexibleContexts #-}
module Archivist.Event
  ( Event       -- type only, no (..)
  , mkEvent
  , eventId
  , timestamp
  , payload
  ) where

data Event e = Event
  { payload   :: e
  , eventId   :: String
  , timestamp :: String
  } deriving (Eq, Ord)

instance Show e => Show (Event e) where
  show e = "<" ++ eventId e ++ " @ " ++ timestamp e ++ ": " ++ show (payload e) ++ ">"

mkEvent :: e -> String -> String -> Event e
mkEvent p i t = Event { payload = p, eventId = i, timestamp = t }
```

The export list omits the `Event (..)` constructor — only the *type*, the smart constructor, and the field accessors are exposed.

Rewrite `src/Archivist/Stream.hs`:

```haskell
module Archivist.Stream
  ( Stream          -- type only
  , Sealed
  , Unsigned
  , streamId
  , events
  , eventCount
  , emptyUnsigned
  , emptySealed
  , appendUnsigned
  , sealStream
  , verify
  , replay
  , module Archivist.Event
  ) where

import Data.List (foldl')
import Archivist.Event

-- Empty types as type-level tags
data Sealed
data Unsigned

data Stream e s = Stream
  { streamId :: String
  , events   :: [Event e]
  }

deriving instance Eq  e => Eq  (Stream e s)
deriving instance Show e => Show (Stream e s)
-- (You may need {-# LANGUAGE StandaloneDeriving #-} at the top.)

eventCount :: Stream e s -> Int
eventCount = length . events

-- Smart constructors
emptyUnsigned :: String -> Stream e Unsigned
emptyUnsigned sid = Stream { streamId = sid, events = [] }

emptySealed :: String -> Stream e Sealed
emptySealed sid = Stream { streamId = sid, events = [] }

-- Append is only legal on Unsigned streams (type-enforced)
appendUnsigned :: Event e -> Stream e Unsigned -> Stream e Unsigned
appendUnsigned e s = s { events = events s ++ [e] }

-- Seal: same runtime value, different type tag
sealStream :: Stream e Unsigned -> Stream e Sealed
sealStream s = Stream { streamId = streamId s, events = events s }

-- Verify is only legal on Sealed streams (type-enforced)
verify :: Stream e Sealed -> Bool
verify _ = True   -- real cryptographic verification arrives in Lesson 10

-- Replay still works for any seal status
replay :: (a -> Event e -> a) -> a -> Stream e s -> a
replay step seed stream = foldl' step seed (events stream)
```

You'll need this language extension at the top of `Stream.hs`:

```haskell
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleContexts   #-}
```

And update `src/Archivist/Projection.hs` so its functions are polymorphic in seal status:

```haskell
countEvents   :: Stream e s -> Int
latestPayload :: Stream String s -> Maybe String   -- payloads still String for these projections; or generalize
payloadCounts :: Stream String s -> [(String, Int)]
```

`countEvents` works for any `Stream e s`. `latestPayload` and `payloadCounts` operate on payload contents, so they stay specialized to `String` payloads for now.

Update `archivist.cabal` if you added any modules (you didn't — just changed signatures).

### Updating existing tests

Existing `EventSpec` and `StreamSpec` tests will fail to compile because of the type changes. Update them:

- Wherever `Stream` appeared, it now needs two parameters: `Stream String Unsigned` for the existing tests.
- `emptyStream` is gone — use `emptyUnsigned`.
- `appendToStream` is gone — use `appendUnsigned`.

This *churn* is itself part of the lesson: when you change a foundational type, the compiler tells you every place that needs updating. Lean into it.

---

## Verify

```sh
runghc check.hs
```

Then, just for the satisfaction of it: uncomment one of the lines from `SealCompileErrors.txt` in a real file, run `cabal build`, and read the error. That's the type system catching a bug that a runtime error never would have.

---

## Self-check

1. What does "phantom type parameter" mean? Why is it called phantom?
2. Why is **not exporting the data constructor** essential to making phantoms safe?
3. What stops a caller from writing `Stream { streamId = "x", events = [] } :: Stream String Sealed` directly?
4. Why do `countEvents` and `replay` work on `Stream e s` for any `s`?
5. We added `emptySealed` for test convenience. In a stricter design, should it exist at all? Argue both sides.

---

## Stretch

- Try writing a function `appendSealed :: Event e -> Stream e Sealed -> Stream e Sealed`. Then read the project context document again — *should* this exist? Why not? (Hint: re-read the sealing modes table.)
- Replace `data Sealed` / `data Unsigned` with a *kind*-promoted enum using `DataKinds`:
    ```haskell
    {-# LANGUAGE DataKinds #-}
    data SealStatus = Sealed | Unsigned   -- now lives at the type level too
    -- and: data Stream e (s :: SealStatus) = ...
    ```
  This is the *modern* version of what we did. Type-safer because `Stream e Int` (using `Int` as a seal tag) is now also a type error.
- Make `Stream e s` an instance of `Foldable`. Now `length`, `null`, `foldr`, and `toList` all work on a stream for free.

---

## Design choices baked into this lesson

- **Phantom tags as empty data types (`data Sealed`, `data Unsigned`)** — the classic approach. Modern alternative: `DataKinds` promotes a sum type to the type level so the *kind* of the tag is checked too (preventing nonsense like `Stream e Int`). I went with empty data types because they need zero extensions; the Stretch points you at `DataKinds` if you want the upgrade.
- **`emptySealed :: String -> Stream e Sealed` exists** — for test convenience. The project context says retroactive sealing isn't allowed; arguably an empty sealed stream is fine because there's nothing to seal *retroactively*, but you can also argue that the only valid path to `Sealed` should be through `sealStream`. I left both arguments to you (it's in self-check). If you want strict, remove `emptySealed` and have tests build via `sealStream . emptyUnsigned`.
- **`verify _ = True`** — placeholder. L10 wires in the real check. If you want, leave a `TODO` or `error "L10"` instead — but then your tests assert that verify *fails*, which complicates this lesson's flow.
- **No `appendSealed` yet** — the project doc says new events in sealed mode get sealed and added. Adding events to a sealed stream requires recomputing the hash chain, which can only happen in L10. Holding the line here keeps L8 clean.
- **`Event` constructor unexported, field accessors exported** — partial smart-constructor pattern. Strictly, you'd hide the accessors too and expose only `payload`/`eventId`/`timestamp` functions. The leak is harmless for now.
- **`Stream`'s constructor `Stream` is also not exported** — same reasoning. Only the type and the smart constructors are public. Verify your export lists.

---

## Done?

`cabal test` is green → **move on to [Lesson 9](../09-gadts/README.md), the GADT showpiece.**
