# Lesson 5 — `Maybe` and `Either`: total functions, errors without exceptions

## Where you are

Your repo-root Cabal project has `Archivist.Event`, `Archivist.Stream`, an `archivist-demo` executable, and a green Hspec test suite. Welcome to **Act II — *It's a real event store.*** Five lessons from here culminate in the GADT seal-status showpiece.

## Learning goal

- Understand **partial vs. total** functions, and why partials are a code smell
- Use `Maybe a = Nothing | Just a` to encode "this might not be here"
- Use `Either e a = Left e | Right a` to encode "this might fail with a reason"
- Pattern-match on both, and meet the handy helpers: `maybe`, `either`, `fromMaybe`, `mapMaybe`
- Get a first taste of `fmap` (and write it off as "I'll meet this properly soon")

## Delivery goal

Add three new functions to the project, with tests:

1. `Archivist.Stream.lookupEvent :: String -> Stream -> Maybe Event` — find an event by its `eventId`. `Nothing` if no event with that id exists.
2. `Archivist.Stream.findByPayload :: String -> Stream -> Maybe Event` — return the *first* event whose `payload` equals the given string.
3. A new module `Archivist.Validation` exporting `validateEvent :: Event -> Either String Event`. Rules:
    - Reject if `payload` is empty → `Left "payload must not be empty"`
    - Reject if `eventId` is empty → `Left "eventId must not be empty"`
    - Reject if `timestamp` is empty → `Left "timestamp must not be empty"`
    - Otherwise → `Right event`

Wire the new module into `archivist.cabal`'s `exposed-modules` list and add a `test/Archivist/ValidationSpec.hs`.

---

## Concept warm-up (20 min)

### Partial vs. total functions

A **partial** function blows up on some inputs:

```haskell
head []     -- *** Exception: Prelude.head: empty list
1 `div` 0   -- *** Exception: divide by zero
```

A **total** function returns a sensible value for every input of its declared type. Total > partial, almost always. `Maybe` and `Either` are the two basic tools to turn partial functions into total ones.

### `Maybe a = Nothing | Just a`

A `Maybe a` is either nothing or a value:

```haskell
:t Nothing             -- Maybe a
:t Just 5              -- Num a => Maybe a
:t Just "hello"        -- Maybe String

-- Pattern-match the same way you'd match any sum type:
let describe m = case m of
                   Nothing  -> "missing"
                   Just x   -> "found " ++ show x
describe (Just 7)
describe Nothing
```

Helpers worth knowing:

```haskell
import Data.Maybe (fromMaybe, mapMaybe, isJust, isNothing, fromJust)

fromMaybe 0 Nothing       -- 0       (default if Nothing)
fromMaybe 0 (Just 9)      -- 9
mapMaybe (\x -> if even x then Just (x*10) else Nothing) [1,2,3,4]
-- [20, 40]                (filter + transform in one)
-- fromJust  -- avoid; it's partial. The whole point of Maybe is to dodge this.
```

There's also the `maybe` *function*, which is `Maybe`'s eliminator:

```haskell
:t maybe
-- maybe :: b -> (a -> b) -> Maybe a -> b

maybe "missing" (\x -> "found " ++ show x) (Just 7)
-- "found 7"
```

Read `maybe d f m` as: "if `m` is `Nothing`, return `d`; otherwise apply `f` to its value."

### `Either e a = Left e | Right a`

`Either` is `Maybe`'s big sibling: it carries information about *why* something failed.

```haskell
:t Left "bad input"        -- Either [Char] a
:t Right 42                -- Num b => Either a b

-- The convention is: Left for failure, Right for success.
-- (Mnemonic: "right" is correct.)

let safeDiv x 0 = Left "divide by zero"
    safeDiv x y = Right (x `div` y)

safeDiv 10 2     -- Right 5
safeDiv 10 0     -- Left "divide by zero"
```

And `either` is its eliminator:

```haskell
:t either
-- either :: (a -> c) -> (b -> c) -> Either a b -> c

either ("error: " ++) show (safeDiv 10 0)
either ("error: " ++) show (safeDiv 10 2)
```

### A tiny taste of `fmap`

Both `Maybe` and `Either e` support a function called `fmap`: "apply a function to the value inside, if there is one":

```haskell
fmap (+1) (Just 5)     -- Just 6
fmap (+1) Nothing      -- Nothing
fmap (*2) (Right 5)    -- Right 10
fmap (*2) (Left "x")   -- Left "x"
```

You'll meet `fmap` properly in Lesson 6 as part of the `Functor` typeclass. For now, just notice: it's a way to operate on a value *inside* a container without unwrapping it.

---

## Read the tests first

Open `test/Archivist/StreamSpec.hs` and add a `describe "lookupEvent"` block:

```haskell
  describe "lookupEvent" $ do
    let s = appendToStream (mkEvent "p2" "evt-2" "t2")
          $ appendToStream (mkEvent "p1" "evt-1" "t1")
          $ emptyStream "orders"

    it "returns Just the event when the id is present" $
      fmap eventId (lookupEvent "evt-1" s) `shouldBe` Just "evt-1"

    it "returns Nothing when the id is missing" $
      lookupEvent "nope" s `shouldBe` Nothing

    it "returns Nothing on an empty stream" $
      lookupEvent "anything" (emptyStream "x") `shouldBe` Nothing

  describe "findByPayload" $ do
    let s = appendToStream (mkEvent "shipped" "evt-3" "t3")
          $ appendToStream (mkEvent "order"   "evt-2" "t2")
          $ appendToStream (mkEvent "order"   "evt-1" "t1")
          $ emptyStream "orders"

    it "returns the first matching event (oldest)" $
      fmap eventId (findByPayload "order" s) `shouldBe` Just "evt-1"

    it "returns Nothing when no event matches" $
      findByPayload "absent" s `shouldBe` Nothing
```

Create `test/Archivist/ValidationSpec.hs`:

```haskell
module Archivist.ValidationSpec (spec) where

import Test.Hspec
import Archivist.Event
import Archivist.Validation

spec :: Spec
spec = describe "validateEvent" $ do
  let good = mkEvent "p" "id" "t"

  it "accepts a fully-populated event" $
    validateEvent good `shouldBe` Right good

  it "rejects an empty payload" $
    validateEvent (mkEvent "" "id" "t")
      `shouldBe` Left "payload must not be empty"

  it "rejects an empty eventId" $
    validateEvent (mkEvent "p" "" "t")
      `shouldBe` Left "eventId must not be empty"

  it "rejects an empty timestamp" $
    validateEvent (mkEvent "p" "id" "")
      `shouldBe` Left "timestamp must not be empty"

  it "reports payload errors before eventId errors when both fail" $
    -- Order matters for predictable user-facing messages
    validateEvent (mkEvent "" "" "t")
      `shouldBe` Left "payload must not be empty"
```

Remember to add `Archivist.ValidationSpec` to `other-modules:` in your `test-suite` stanza in `archivist.cabal`.

---

## Build it

### `lookupEvent` and `findByPayload`

Add to `src/Archivist/Stream.hs`. One natural shape:

```haskell
import Data.List (find)

lookupEvent :: String -> Stream -> Maybe Event
lookupEvent target = find (\e -> eventId e == target) . events

findByPayload :: String -> Stream -> Maybe Event
findByPayload p = find (\e -> payload e == p) . events
```

`Data.List.find :: (a -> Bool) -> [a] -> Maybe a` is the workhorse. Note how the type already encodes "might not find it" — that's totality at the type level.

Don't forget to add these to the export list at the top of the module.

### `Archivist.Validation`

Create `src/Archivist/Validation.hs`:

```haskell
module Archivist.Validation
  ( validateEvent
  ) where

import Archivist.Event

validateEvent :: Event -> Either String Event
validateEvent e
  | null (payload e)   = Left "payload must not be empty"
  | null (eventId e)   = Left "eventId must not be empty"
  | null (timestamp e) = Left "timestamp must not be empty"
  | otherwise          = Right e
```

The `| ... =` style is **guards** — a chain of boolean conditions with `otherwise` (just an alias for `True`) at the end. They're often cleaner than nested `if`/`else`.

Add the module to the `library`'s `exposed-modules` in `archivist.cabal`.

---

## Verify

```sh
runghc check.hs
```

Green `cabal test` → done.

---

## Self-check

1. What does "total function" mean? Give one example of a partial function in `Prelude` and the total replacement.
2. What's the difference between `Maybe` and `Either`? When would you reach for each?
3. Explain `fmap (+1) (Just 5) = Just 6` in your own words.
4. Why is `fromJust` discouraged?
5. Read this signature: `mapMaybe :: (a -> Maybe b) -> [a] -> [b]`. What does it do, just from the type? (This is a recurring Haskell move — *read the types*.)

---

## Stretch

- Write `validateEvents :: [Event] -> Either String [Event]` — fail on the *first* invalid event. (Hint: `traverse`. Try `:t traverse` in GHCi and see if you can guess.)
- Write a variant `validateEventsAll :: [Event] -> Either [String] [Event]` that collects *all* errors instead of stopping at the first. (Hint: this is `Validation`, the cousin of `Either` that accumulates. Look up `Data.Validation` if curious.)
- Add a `lookupEventOrError :: String -> Stream -> Either String Event` to `Archivist.Stream` — same shape as `lookupEvent` but explains the failure.

---

## Design choices baked into this lesson

- **Validation rules: "non-empty" for all three fields** — minimal. Real-world checks might validate timestamp *format* (ISO-8601), enforce eventId uniqueness within a stream, or require structured payloads. Add rules as your domain demands.
- **Error type is `String`** — fine for L5. A production codebase usually defines a typed error ADT like `data ValidationError = EmptyPayload | EmptyEventId | EmptyTimestamp | BadTimestampFormat String` so callers can pattern-match instead of parsing strings.
- **Stops at the first failure** — `Either` short-circuits. The Stretch (`Validation`-style accumulating errors) is the alternative when UX wants *all* problems at once.
- **`validateEvent` lives in its own module `Archivist.Validation`** — could just live in `Archivist.Event`. Separate module gives room for the validator set to grow (per-payload-type validators, registry, etc.) without bloating the event module.
- **Order of rules: payload → eventId → timestamp** — arbitrary; the test enforces it. Pick whichever order produces the user-facing message you'd want first.

---

## Done?

`cabal test` is green → **move on to [Lesson 6](../06-typeclasses/README.md).**
