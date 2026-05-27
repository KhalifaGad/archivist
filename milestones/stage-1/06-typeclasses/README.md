# Lesson 6 — Typeclasses: shared behavior, not shared data

## Where you are

`Maybe` and `Either` are behind you. You've been deriving `Show` and `Eq` since Lesson 2 without thinking about what that really means. Time to think about it.

## Learning goal

- Understand that a **typeclass** describes shared *behavior* (what operations a type supports), not shared structure
- Read constraint syntax: `Eq a => a -> a -> Bool` means "for any type `a` that has `Eq`, ..."
- Use `deriving` (the easy path) and write **custom instances** (the explicit path)
- Meet four foundational classes you'll use everywhere: `Show`, `Eq`, `Ord`, `Functor`
- Define a tiny typeclass of your own

This is *the* lesson that often clicks for newcomers: typeclasses are Haskell's answer to interfaces, traits, and protocols — but better, because they're not tied to the type's definition.

## Delivery goal

1. Add `deriving Ord` to `Event` and `Stream`. Verify the order is sensible.
2. Write a **custom `Show` instance** for `Event` — replace the derived noisy one with a compact `<evt-1 @ t1: order-placed>` format. (Important: this means *not* deriving `Show`. You'll write it by hand.)
3. Define your first typeclass in `src/Archivist/Identifiable.hs`:
    ```haskell
    class Identifiable a where
      identifier :: a -> String
    ```
    Provide instances for `Event` (returns `eventId e`) and `Stream` (returns `streamId s`).
4. Write a polymorphic function `describe :: (Identifiable a, Show a) => a -> String` that returns `"<id: <identifier>> = <show>"`.

---

## Concept warm-up (25 min)

### What is a typeclass?

A typeclass is a **set of operations** that a type may implement. The class declares the operations; an **instance** provides them for a specific type.

```haskell
-- The class is just a contract:
class MyEq a where
  myEq :: a -> a -> Bool

-- An instance fills in the contract for a specific type:
instance MyEq Int where
  myEq x y = x == y

instance MyEq Bool where
  myEq True True   = True
  myEq False False = True
  myEq _ _         = False

-- A function can require its argument's type to have an instance:
allSame :: MyEq a => [a] -> Bool
allSame []     = True
allSame [_]    = True
allSame (x:y:rest) = myEq x y && allSame (y:rest)
```

The `MyEq a =>` part is a **constraint**. Read it: "for any type `a`, *provided that `a` has a `MyEq` instance*, this function works."

The mental model: typeclasses are like interfaces in other languages, except:
- Instances can be added **after the type is defined**, even in a different package
- A function can have **multiple constraints** at once: `(Eq a, Show a) => ...`
- Some classes have **superclass relationships** (e.g., `Ord` requires `Eq` first)

### The foundational four

#### `Show` — convert to `String`

```haskell
:t show              -- Show a => a -> String
show 5               -- "5"
show "hello"         -- "\"hello\""
show [1,2,3]         -- "[1,2,3]"
```

`Show` is for programmer-facing output, not user-facing. `show "hello"` keeps the quotes because that's how you'd type the value back as Haskell source.

#### `Eq` — equality

```haskell
:t (==)              -- Eq a => a -> a -> Bool
```

Two values of the same type can be compared. Most types you'll meet have it.

#### `Ord` — ordering

```haskell
:t compare           -- Ord a => a -> a -> Ordering
:t (<)               -- Ord a => a -> a -> Bool

compare 3 5          -- LT
compare "a" "b"      -- LT
```

`Ord` *requires* `Eq` first (you can't define ordering without equality). For records, `deriving Ord` orders **lexicographically by field declaration order** — first field first, ties broken by the second, etc. That's why field order in records is a design decision, not just cosmetic.

#### `Functor` — "things with one hole"

A first peek. You'll meet this fully when you need it:

```haskell
class Functor f where
  fmap :: (a -> b) -> f a -> f b
```

`Maybe` is a `Functor`. `[]` is a `Functor`. `Either e` is a `Functor`. They all let you apply a function to whatever is "inside" without unwrapping.

```haskell
fmap (+1) (Just 5)          -- Just 6
fmap (+1) [1,2,3]           -- [2,3,4]
fmap (++"!") (Right "hi")   -- Right "hi!"
```

You're not writing `Functor` instances this lesson. Just notice: `fmap` is the *generalization* of `map`.

### `deriving` vs. hand-written instances

```haskell
data Color = Red | Green | Blue deriving (Show, Eq, Ord)

show Red          -- "Red"
Red == Red        -- True
compare Red Blue  -- LT
```

`deriving (Show, Eq, Ord)` writes the obvious instance for you. You can also write instances by hand when "obvious" isn't what you want:

```haskell
data Color = Red | Green | Blue deriving (Eq, Ord)

instance Show Color where
  show Red   = "🔴"
  show Green = "🟢"
  show Blue  = "🔵"
```

Now `show Red` prints `"🔴"` — your version, not the derived one.

A type **cannot have two `Show` instances** simultaneously. So if you write a custom one, drop `Show` from the `deriving` list.

### Defining your own typeclass

```haskell
class HasName a where
  nameOf :: a -> String

data Cat  = Cat  { catName  :: String }
data Dog  = Dog  { dogName  :: String }

instance HasName Cat where nameOf = catName
instance HasName Dog where nameOf = dogName

-- A polymorphic function over any HasName:
greet :: HasName a => a -> String
greet x = "Hello, " ++ nameOf x
```

`greet` doesn't care whether the thing is a cat or a dog — only that it has a name.

---

## Read the tests first

Add to `test/Archivist/EventSpec.hs`:

```haskell
  describe "Ord Event" $ do
    it "orders events lexicographically by field declaration order" $ do
      -- payload comes first, so "a..." < "b..."
      compare (mkEvent "a" "id" "t") (mkEvent "b" "id" "t") `shouldBe` LT

  describe "custom Show Event" $ do
    it "renders compactly as <id @ timestamp: payload>" $
      show (mkEvent "order-placed" "evt-1" "2024-01-01")
        `shouldBe` "<evt-1 @ 2024-01-01: order-placed>"
```

Create `test/Archivist/IdentifiableSpec.hs`:

```haskell
module Archivist.IdentifiableSpec (spec) where

import Test.Hspec
import Archivist.Event
import Archivist.Stream
import Archivist.Identifiable

spec :: Spec
spec = describe "Identifiable" $ do
  it "returns eventId for Events" $
    identifier (mkEvent "p" "evt-1" "t") `shouldBe` "evt-1"

  it "returns streamId for Streams" $
    identifier (emptyStream "orders") `shouldBe` "orders"

  it "describe works for any Identifiable + Show value" $ do
    let e = mkEvent "order-placed" "evt-1" "2024-01-01"
    describe' e `shouldContain` "evt-1"
    describe' e `shouldContain` "order-placed"
  where
    describe' = describe   -- alias to avoid name clash with Hspec's `describe`
```

(That last bit shows a real-world wart: `describe` is also Hspec's function name. We rename ours when imported, or call it something else like `identityDescription`.)

Add `Archivist.IdentifiableSpec` to `other-modules:` in your `test-suite`.

---

## Build it

### Add `Ord` derivations

In `src/Archivist/Event.hs`:

```haskell
data Event = Event
  { payload   :: String
  , eventId   :: String
  , timestamp :: String
  } deriving (Eq, Ord)   -- note: Show is GONE; custom instance below
```

### Custom `Show` for `Event`

Right under the `data Event` definition:

```haskell
instance Show Event where
  show e = "<" ++ eventId e ++ " @ " ++ timestamp e ++ ": " ++ payload e ++ ">"
```

In `src/Archivist/Stream.hs`, you can keep `deriving (Show, Eq, Ord)` for `Stream` — the derived `Show` is fine there.

### The `Identifiable` typeclass and module

Create `src/Archivist/Identifiable.hs`:

```haskell
module Archivist.Identifiable
  ( Identifiable (..)
  , describe
  ) where

import Archivist.Event
import Archivist.Stream

class Identifiable a where
  identifier :: a -> String

instance Identifiable Event where
  identifier = eventId

instance Identifiable Stream where
  identifier = streamId

describe :: (Identifiable a, Show a) => a -> String
describe x = "<id: " ++ identifier x ++ "> = " ++ show x
```

Add `Archivist.Identifiable` to the library's `exposed-modules` in `archivist.cabal`.

---

## Verify

```sh
runghc check.hs
```

---

## Self-check

1. What's the difference between a class declaration and an instance?
2. Read this signature: `(Eq a, Ord a) => a -> a -> Bool`. What does the part before `=>` mean?
3. Why can't you have two `Show` instances for the same type?
4. The derived `Ord` for `Event` sorts by `payload` first. Why? How would you change it?
5. What does `fmap` generalize that you already knew?

---

## Stretch

- Write `instance Identifiable a => Identifiable [a]` returning a comma-joined list of identifiers. You'll need to add `import Data.List (intercalate)`. (This is your first **polymorphic instance** — *for any type `a` that's `Identifiable`, lists of `a` are also `Identifiable`*.)
- Sort a `[Event]` by timestamp instead of declaration order. Hint: `sortBy (comparing timestamp)` from `Data.List` and `Data.Ord`.
- Read `:i Functor` and `:i Foldable` in GHCi. Don't try to understand everything — just notice how typeclasses describe a *web of capabilities* a type can support.

---

## Design choices baked into this lesson

- **Custom `Show Event` format `<id @ timestamp: payload>`** — my taste. Pick whatever shape looks good to you; the test asserts the exact string, so if you change the format, update the spec.
- **`Archivist.Identifiable` is a typeclass I invented for teaching** — it's *not* in the project context document. It's useful as a foreshadowing of how typeclasses scale; if you don't end up using it after this lesson, deleting it later costs nothing.
- **Derived `Ord Event` orders by payload first** — that falls out of declaration order. If you want time-ordered events (probably what you actually want eventually), write a manual `Ord` instance comparing `timestamp` first, or `sortBy (comparing timestamp)` at use sites.
- **`describe` clashes with Hspec's `describe`** — the test file renames it. In a real project, this is a smell — pick a better name (`identityLabel`, `formatIdentity`, etc.).

---

## Done?

`cabal test` is green → **move on to [Lesson 7](../07-folds/README.md).**
