# Lesson 2 — Algebraic Data Types and pattern matching

## Where you are

You have `Archivist.hs` from Lesson 1: `Event` is a 3-tuple, accessors are tuple-destructuring functions. It works, but you felt the friction. Adding a field means renaming a 3-tuple to a 4-tuple, and every accessor breaks.

## Learning goal

- Define **product types** with `data` and **records** for named fields
- Define **sum types** ("or" types) like `data SealStatus = Sealed | Unsigned`
- Pattern-match on constructors
- Use `deriving (Show, Eq)` to get printing and equality for free — and know what that actually means

This is the lesson where Haskell starts feeling like a *design tool* and not just a language.

## Delivery goal

Rewrite `Archivist.hs` so:

- `Event` is a **record** with named fields: `payload`, `eventId`, `timestamp` — all `String`.
- A new type `Stream` wraps an event log with an identifier: `streamId :: String` and `events :: [Event]`.
- A new sum type `SealStatus = Unsigned | Sealed` exists. *We don't use it yet* — it's foreshadowing for Lesson 8. Just define it.
- Functions: `emptyStream`, `appendToStream`, `eventCount`.

Bring `Archivist.hs` over from Lesson 1's directory to this one as your starting point, then evolve it.

---

## Concept warm-up (20 min)

### Product types

A product type bundles things together. The tuple `(Int, String)` is a product. Records are tuples with **named fields**:

```haskell
-- In a scratch file or :{ ... :} block in GHCi
data Point = Point Int Int  deriving (Show, Eq)
let p = Point 3 4
p

-- Same idea, with names:
data Person = Person { name :: String, age :: Int } deriving (Show, Eq)
let me = Person { name = "Khalifa", age = 30 }
name me
age me
me { age = 31 }   -- record update syntax — returns a NEW Person; the old one is unchanged
```

The compiler auto-generates `name :: Person -> String` and `age :: Person -> Int` for you. Records aren't magic — they're sugar over a positional product with accessor functions.

### Sum types

A sum type is "one of several alternatives":

```haskell
data SealStatus = Unsigned | Sealed deriving (Show, Eq)
let s = Sealed
s

-- Pattern matching:
let describe x = case x of
                   Sealed   -> "tamper-evident"
                   Unsigned -> "plain append-only"
describe Sealed
describe Unsigned
```

A sum type can also carry data per branch — you'll meet that pattern in Lesson 5 with `Maybe`.

### `deriving` — what it actually does

`deriving (Show, Eq)` tells the compiler: "Write the boilerplate `show` and `==` functions for this type." `Show` lets you print a value. `Eq` lets you compare two values with `==`. Without `Show`, GHCi can't display your value. Without `Eq`, you can't write `x == y`.

You're not required to derive these — you can write custom instances. We will, later. For now, derive them everywhere.

---

## Read the tests first

Open `check.hs`. The contract:

- `Event` is constructible as `Event { payload = ..., eventId = ..., timestamp = ... }`
- The field accessors return the right pieces
- `Event` derives `Show` and `Eq`
- `Stream` has `streamId` and `events` fields
- `emptyStream "orders"` produces a `Stream` with that id and no events
- `appendToStream` preserves order (same invariant as Lesson 1, just at the `Stream` level)
- `eventCount` returns the number of events
- `SealStatus` exists with two constructors, distinguishable by `==`

---

## Build it

Replace `Archivist.hs` with the record-based version. Sketch (fill in the blanks yourself):

```haskell
module Archivist where

data Event = Event
  { payload   :: String
  , eventId   :: String
  , timestamp :: String
  } deriving (Show, Eq)

data Stream = Stream
  { streamId :: String
  , events   :: [Event]
  } deriving (Show, Eq)

data SealStatus = Unsigned | Sealed deriving (Show, Eq)

emptyStream    :: String -> Stream
appendToStream :: Event  -> Stream -> Stream
eventCount     :: Stream -> Int
mkEvent        :: String -> String -> String -> Event
```

For `appendToStream`, you have a choice of styles:

```haskell
-- Style A: record update syntax
appendToStream e s = s { events = events s ++ [e] }

-- Style B: pattern-match in the function head
appendToStream e (Stream sid es) = Stream sid (es ++ [e])
```

Both work. Try writing each in GHCi and *feel* the difference. Style A scales better when there are many fields. Style B is more explicit about what's happening.

### A note on the cons-vs-append tension

`events s ++ [e]` is O(n) — it walks the whole list to find the end. Cons (`e : events s`) is O(1) but would put new events at the *front*, breaking our ordering.

The "real" fix is to store events in reverse order internally and reverse on read, or use a smarter data structure. We won't bother in Stage 1 — correctness first, performance when it matters. Just notice the trade-off exists. This is the kind of thinking databases live and breathe.

---

## Verify

```sh
runghc check.hs
```

Expect a list of ticks ending in `PASS ✓`.

---

## Self-check

1. What does "product type" mean? What does "sum type" mean? Give one example of each from Haskell.
2. What does `deriving (Show, Eq)` actually generate? What would you lose by removing it?
3. What does `me { age = 31 }` return? Why doesn't it mutate `me`?
4. Why might you prefer a record over a 3-tuple even if both store the same data?
5. We defined `SealStatus` but didn't use it. Where in the project context document does it eventually matter?

---

## Stretch

- Try this in GHCi: `data Maybe' a = Nothing' | Just' a deriving Show`. You've just defined a *parameterized* sum type — like the standard `Maybe`, with `a` as a type variable. Lesson 5 will use this for real.
- Write `firstEvent :: Stream -> Maybe Event` returning the oldest event, or `Nothing` if empty. (Use the built-in `Maybe`.)
- `data Tree a = Leaf | Node (Tree a) a (Tree a) deriving Show` — a binary tree. Try inserting a few values. Recursive data types are where Haskell starts feeling powerful.

---

## Design choices baked into this lesson

- **Record field order still `(payload, eventId, timestamp)`** — re-question now that it's a record. `Ord` derivation in L6 will sort lexicographically by this order.
- **`Stream` wraps `[Event]` with a `streamId`** — alternative: don't have a `Stream` type at all and store everything as `Map StreamId [Event]` at the storage layer. The wrapper keeps each function signature honest about what kind of value it handles.
- **`streamId :: String`** — in production, `newtype StreamId = StreamId String` prevents accidentally swapping a stream id with an event id or a free-form `String`. Adding the newtype is straightforward later; I left it out to keep this lesson focused.
- **`SealStatus` is declared but unused** — it's *foreshadowing only*. L8 and L9 replace it with phantom tags and a GADT. Resist the urge to use it now.

---

## Done?

`runghc check.hs` prints `PASS ✓` → **move on to [Lesson 3](../03-io-and-pure/README.md).**
