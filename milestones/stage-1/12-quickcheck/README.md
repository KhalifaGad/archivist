# Lesson 12 — QuickCheck: properties that prove your invariants

## Where you are

You have a typed, hash-chained, SQLite-persisted event store. Your Hspec suite has dozens of example-based tests. They all pass. So… how do you know there isn't some sneaky combination of inputs your example tests never tried?

That's the question **property-based testing** answers. Instead of "for this specific input, the output is X", you state a *property that must hold for every possible input*, and QuickCheck generates a hundred random cases trying to break you.

When QuickCheck finds a failure, it **shrinks** the input — repeatedly tries smaller variants until it has the minimal example that still fails. The resulting bug report is gold.

## Learning goal

- Understand property-based testing — why a single property is often worth many example tests
- Use QuickCheck via `hspec-quickcheck` to integrate properties into your existing Hspec suite
- Write `Arbitrary` instances — generators that produce random values of your types
- Use combinators: `listOf`, `oneof`, `frequency`, `sized`, `choose`
- Recognize when a property is *trivially* true (a smell) and when it actually exercises behavior

## Delivery goal

A new spec module `test/Archivist/PropertiesSpec.hs` with these properties (or your equivalents):

1. **Append-only / ordering invariant** — for any unsigned stream `s` and event `e`:
    > `unsignedEvents (appendUnsigned e s) == unsignedEvents s ++ [e]`
2. **Append preserves the streamId** — for any `s` and `e`:
    > `streamId (appendUnsigned e s) == streamId s`
3. **`replay` equals `foldl'` over events** — for any function `f`, seed `z`, unsigned `s`:
    > `replayUnsigned f z s == foldl' f z (unsignedEvents s)`
4. **Round-trip through SQLite preserves an unsigned stream** — for any stream `s`:
    > `load(persist(s)) == s` (modulo streamId — both sides anchored to a known id)
5. **Sealed verify holds for any honestly-built stream** — for any unsigned `s`:
    > `verify (sealStream s) == True`
6. **Tampering with any event breaks verify** — for any unsigned `s` with at least one event:
    > `verify (tamperFirst (sealStream s)) == False`

Wire `Archivist.PropertiesSpec` into `archivist.cabal`'s test-suite `other-modules`, add `QuickCheck` and `hspec-quickcheck` to test deps.

---

## Concept warm-up (25 min)

### From examples to properties

An example test for `reverse`:

```haskell
it "reverses [1,2,3] to [3,2,1]" $
  reverse [1, 2, 3] `shouldBe` [3, 2, 1]
```

A property for `reverse`:

```haskell
prop "reverse is its own inverse" $
  \xs -> reverse (reverse xs) == (xs :: [Int])
```

The property runs 100 (configurable) randomly-generated lists. If any fail, it shrinks the offending list to the minimal version that still fails and reports it.

A single well-chosen property often replaces *many* example tests. But properties don't replace examples entirely — examples document *intent* and serve as readable docs. Use both.

### `Arbitrary`

`Arbitrary` is the typeclass for "random generator":

```haskell
class Arbitrary a where
  arbitrary :: Gen a
  shrink    :: a -> [a]    -- default: const []
```

`Gen` is QuickCheck's generator monad. The standard library ships instances for `Int`, `Bool`, `String`, `[a]`, `Maybe a`, tuples, etc. You write your own for domain types.

```haskell
import Test.QuickCheck

instance Arbitrary Event where
  arbitrary = Event
    <$> arbitrary    -- random payload :: String
    <*> arbitrary    -- random eventId
    <*> arbitrary    -- random timestamp
```

The `<$>` / `<*>` pattern from L11's `FromRow` works here too — it's the **applicative** style. Read it as "build an `Event` from three random fields."

But raw `arbitrary :: Gen String` produces *any* `String` — including ones with NUL bytes, which break our hash chain's serialization. So we constrain:

```haskell
import Test.QuickCheck

genSafeString :: Gen String
genSafeString = listOf (elements (['a'..'z'] ++ ['0'..'9'] ++ "-_"))

instance Arbitrary (Event String) where
  arbitrary = mkEvent <$> genSafeString <*> genSafeString <*> genSafeString
```

`elements [...]` picks one element uniformly from a list. `listOf gen` produces a list of zero-or-more values from `gen`. Composing them gives "list of safe chars" → a safe string.

### Generators worth knowing

- `arbitrary :: Gen a` — the default for any `Arbitrary` type
- `choose (lo, hi) :: Gen Int` — uniform in a range
- `elements [a, b, c] :: Gen a` — pick one
- `oneof [gen1, gen2] :: Gen a` — pick one of these *generators*, run it
- `frequency [(3, gen1), (1, gen2)] :: Gen a` — weighted version of `oneof`
- `listOf gen :: Gen [a]` — list of arbitrary length
- `vectorOf n gen :: Gen [a]` — list of exactly n
- `sized :: (Int -> Gen a) -> Gen a` — generators can scale with the test size

Pair these with `forAll gen $ \x -> ...` if you want a one-off generator inside a property.

### `hspec-quickcheck` integration

```haskell
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

spec :: Spec
spec = describe "List" $ do
  prop "reverse is its own inverse" $
    \xs -> reverse (reverse xs) === (xs :: [Int])
```

`prop` is `it` for properties. `===` is `==` with better failure messages (it prints both sides on mismatch).

### When a property is trivially true

```haskell
prop "addition is closed under Int" $
  \a b -> (a + b :: Int) `seq` True   -- always True, tests nothing
```

A property is only useful if a buggy implementation would *fail* it. Always ask: "would a wrong implementation pass this?" If the answer is yes, refine.

For example: testing that `length (xs ++ ys) == length xs + length ys` actually exercises `++`'s correctness because a buggy `++` (say, one that drops elements) would fail.

---

## Read the tests first

`test/Archivist/PropertiesSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Archivist.PropertiesSpec (spec) where

import Data.List (foldl')
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import System.IO (hClose)
import System.IO.Temp (withSystemTempFile)
import Database.SQLite.Simple (close)

import Archivist.Event
import Archivist.Stream
import Archivist.Storage.SQLite

-- ----- Generators -----

genSafeString :: Gen String
genSafeString = listOf1 (elements (['a'..'z'] ++ ['0'..'9'] ++ "-_"))
  -- listOf1 = "list with at least one element" -- avoids empty strings that
  -- our validation would reject. Empty strings remain testable via separate
  -- example-based tests if needed.

genEvent :: Gen (Event String)
genEvent = mkEvent <$> genSafeString <*> genSafeString <*> genSafeString

instance Arbitrary (Event String) where
  arbitrary = genEvent

-- ----- Properties -----

spec :: Spec
spec = do
  describe "appendUnsigned" $ do
    prop "puts the new event at the end of the events list" $
      \e (NonEmptyStreamId sid) events ->
        let s  = foldl' (flip appendUnsigned) (emptyUnsigned sid) events
            s' = appendUnsigned (e :: Event String) s
        in unsignedEvents s' === unsignedEvents s ++ [e]

    prop "preserves the streamId" $
      \e (NonEmptyStreamId sid) events ->
        let s  = foldl' (flip appendUnsigned) (emptyUnsigned sid) (events :: [Event String])
            s' = appendUnsigned (e :: Event String) s
        in streamId s' === sid

  describe "replayUnsigned" $
    prop "matches foldl' over the underlying events" $
      \(NonEmptyStreamId sid) events ->
        let s = foldl' (flip appendUnsigned) (emptyUnsigned sid) (events :: [Event String])
            sumLengths acc e = acc + length (payload e)
        in replayUnsigned sumLengths 0 s === foldl' sumLengths 0 (unsignedEvents s)

  describe "verify" $ do
    prop "is always True for a freshly sealed honest stream" $
      \(NonEmptyStreamId sid) events ->
        verify (sealStream (foldl' (flip appendUnsigned)
                                   (emptyUnsigned sid)
                                   (events :: [Event String])))
        === True

    prop "is False after the first event's payload is mutated" $
      \(NonEmptyStreamId sid) (NonEmptyList events) ->
        let sealed = sealStream (foldl' (flip appendUnsigned)
                                        (emptyUnsigned sid)
                                        (events :: [Event String]))
            tampered = case sealed of
              SealedStream s (se:rest) ->
                SealedStream s
                  (se { sealedEvent = (sealedEvent se) { payload = "EVIL" } } : rest)
              other -> other
        in verify tampered === False

  describe "SQLite round-trip" $
    prop "loadUnsigned (persistUnsignedEvent*) preserves an unsigned stream" $
      \(NonEmptyStreamId sid) events ->
        ioProperty $ withSystemTempFile "qc.db" $ \path h -> do
          hClose h
          conn <- openStore path
          mapM_ (\(i, e) -> persistUnsignedEvent conn sid e i)
                (zip [0..] (events :: [Event String]))
          s' <- loadUnsigned conn sid
          close conn
          pure $ unsignedEvents s' === events

-- ----- Newtype to constrain streamId generation -----

newtype NonEmptyStreamId = NonEmptyStreamId String
  deriving (Show)

instance Arbitrary NonEmptyStreamId where
  arbitrary = NonEmptyStreamId <$> listOf1 (elements (['a'..'z'] ++ "_"))
```

The `NonEmptyStreamId` newtype is a common QuickCheck trick: when you need a constrained generator, wrap a type and give it an `Arbitrary` instance with the constraint baked in.

---

## Build it

The only "build" here is **wiring**, plus making the tests pass:

### Cabal deps

In the test-suite stanza of `archivist.cabal`:

```cabal
                    , QuickCheck     ^>=2.14
                    , hspec-quickcheck ^>=0.5
```

Add to test-suite `other-modules`:

```cabal
                    , Archivist.PropertiesSpec
```

### Iterate

Run `cabal test`. If properties fail, **read the shrunken counter-example**. That's the value: a one-element list or two-char string that exposes the bug. Fix the offending code, run again.

You may discover that your hash serialization or your SQLite types have an edge case the example tests didn't cover. *That's the win.* Fix it in the code, not by weakening the property.

---

## Verify

```sh
runghc check.hs
```

---

## Design choices baked into this lesson

- **`Arbitrary` instances live in test code, not in the library** — the orphan-instance pattern. Putting them in the library would expose `QuickCheck` as a runtime dependency, which is wrong (QuickCheck is a *test* concern). The downside: any other test module that wants the instances has to re-import them.
- **`genSafeString` rejects characters that break serialization** — pragmatic. The "correct" fix is to harden serialization (length-prefixed fields, JSON, CBOR) so any character is safe. We'd rather constrain inputs than retrofit the serializer in Stage 1. Note this leaves a *gap* in the property coverage — flag it in your head.
- **`listOf1` instead of `listOf`** — prevents empty strings, which our validation would reject. Empty inputs are worth testing too, just with separate example tests rather than randomly hitting the validation path.
- **Only six properties** — minimal coverage. Real-world property suites have many more. Notably missing: round-trip for sealed streams; behavior under stream-id collisions; properties about `Archivist.Validation`. Add as appetite allows.
- **No `Arbitrary` for `EventStream`** — instead, properties build streams by folding `appendUnsigned` over `[Event String]`. Defining `Arbitrary` for the GADT means choosing a seal status (you can't randomize that meaningfully), so building "in the property" is cleaner.
- **`prop` runs 100 cases by default** — bump it with `withMaxSuccess`:
  ```haskell
  prop "..." $ withMaxSuccess 1000 $ \x -> ...
  ```
  Useful when investigating intermittent failures; expensive in CI.
- **`ioProperty`** lets a property run an `IO` action and return a `Property`. We use it for the SQLite round-trip. Slower than pure properties — use sparingly, ideally with a small `withMaxSuccess` cap.

---

## Self-check

1. Why does property-based testing complement, not replace, example-based testing?
2. What does *shrinking* do, and why is it so valuable?
3. Why is `prop "reverse (reverse xs) == xs"` a useful property but `prop "x == x"` is not?
4. We use `listOf1` to avoid empty strings. What gap does this leave in our test coverage? How would you close it?
5. Why are `Arbitrary` instances put in test code rather than next to the types they generate?

---

## Stretch

- Add a round-trip property for **sealed** streams: persist, load, then check `verify`. This catches any subtle serialization corruption end-to-end.
- Write a property that exercises **two-stream isolation**: persist events to two different stream-ids and assert that loading each gives only its own events.
- Write an `Arbitrary` instance for `SomeEventStream String` (from the L11 Stretch existential) that uniformly picks `Sealed` or `Unsigned`. Now you can write one polymorphic load round-trip property.
- Read about QuickCheck's `shrink` function. Implement `shrink` for `Event String` so failing cases report a meaningfully reduced event (e.g., shorter payload). The default `shrink _ = []` is fine but leaves bigger counter-examples than necessary.

---

## Done?

`cabal test` is green → **move on to [Lesson 13 — the capstone](../13-capstone/README.md).**
