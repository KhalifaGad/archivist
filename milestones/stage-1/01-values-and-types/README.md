# Lesson 1 — Values, types, and your first `Event`

## Where you are

You finished Lesson 0. `runghc` works. You've seen `:t` in GHCi.

## Learning goal

- Read and write **function type signatures** (`name :: Type -> Type`)
- Know the basic types: `Int`, `String`, `Bool`, **tuples**, **lists**
- Use **type aliases** (`type Foo = ...`) to give meaningful names to types
- Feel the first ergonomic pain of using tuples for structured data — *important*, because Lesson 2 fixes it

## Delivery goal

A single file `Archivist.hs` in this directory that defines:

- `Event` — a type alias for a 3-tuple `(String, String, String)` carrying `(payload, eventId, timestamp)`
- `Log` — a type alias for `[Event]`
- Accessor functions: `payload`, `eventId`, `timestamp`
- A constructor: `mkEvent :: String -> String -> String -> Event`
- An append function: `appendEvent :: Event -> Log -> Log` — adds an event to the **end** of a log (oldest first, newest last). This ordering matters.

---

## Concept warm-up (15 min)

In GHCi:

```haskell
-- Read these as "X has type Y"
:t 'a'              -- Char
:t "abc"            -- [Char]  (a String IS a [Char])
:t True             -- Bool
:t (1, "hi")        -- (Int, String) ish
:t [1, 2, 3]        -- [Int] ish
:t fst              -- (a, b) -> a
:t snd              -- (a, b) -> b

-- Define a function
let inc x = x + 1
:t inc

-- Type signatures are written above definitions in real code:
let add :: Int -> Int -> Int; add x y = x + y
:t add
add 2 3
add 2          -- partial application — gives back a function!
:t add 2       -- Int -> Int
```

Two things to internalize:

1. **`String` is just `[Char]`.** A list of characters. Strings are not special.
2. **Functions of multiple arguments are *curried*.** `add :: Int -> Int -> Int` really means `Int -> (Int -> Int)`. Calling `add 2` gives you back a function that adds 2 to its argument. This is why `add 2 3` works without parentheses around `(2, 3)`.

Now type aliases. A type alias is a nickname:

```haskell
:set -XScopedTypeVariables
type Name = String
let greet :: Name -> String; greet n = "Hi, " ++ n
greet "Khalifa"
```

The compiler treats `Name` and `String` as identical. Aliases exist for *humans reading the code*.

---

## Read the tests first

Open `check.hs` in this directory and read it. It tells you exactly what your `Archivist.hs` must export and how those functions must behave. **Read it before you write any code.** This is the lesson's contract.

A subtle point worth noting now, because the test catches it: `appendEvent e []` must return `[e]`, and `appendEvent e2 [e1]` must return `[e1, e2]` — **oldest first**. If you use the `:` (cons) operator naively, you'll prepend, which breaks the contract. A log of facts is read in *the order they happened*.

---

## Build it

Create `Archivist.hs` in this directory. Start it with this line:

```haskell
module Archivist where
```

For now, treat this as boilerplate. Lesson 4 explains what modules are. We need it here so `check.hs` can `import Archivist`.

Below that, define the type aliases, the constructor, the accessors, and `appendEvent`. Use real type signatures on every top-level definition — it's a habit worth forming now.

Hints (only if stuck):

- `Event` is `(String, String, String)`. Use `fst`, `snd`, or pattern matching `(p, _, _)` to get pieces out.
- Lists in Haskell are built with `:` (cons, prepend) or `++` (concat). `[1, 2] ++ [3]` is `[1, 2, 3]`. `1 : [2, 3]` is `[1, 2, 3]`.
- A function definition with a destructuring argument: `payload (p, _, _) = p`.

---

## Verify

```sh
runghc check.hs
```

You should see a list of ticks ending with `PASS ✓`. Every failing assertion will point at the function and the expectation it broke.

---

## Self-check

1. Why is `String` the same as `[Char]`?
2. What does *currying* mean? Give an example with `add :: Int -> Int -> Int`.
3. What's the difference between `:` and `++`?
4. Why does `appendEvent` use `++ [e]` instead of `e : log`? (Even if you got the test to pass, articulate *why*.)
5. Reading tuples gets awkward when there are more than two or three fields. Imagine an event with 8 fields as a tuple. What problem does that cause for *readers* of the code? (Lesson 2 fixes this.)

---

## Stretch

- Implement `eventCount :: Log -> Int` two ways: with `length`, and with explicit recursion. Compare them in GHCi.
- Implement `latest :: Log -> Maybe Event` — return the last event if there is one. You haven't met `Maybe` formally yet (Lesson 5) but its shape is `Maybe a = Nothing | Just a`. Try it.
- In GHCi, run `:i (:)`. What does it tell you?

---

## Design choices baked into this lesson

These are things I picked that aren't dictated by `project_context.md`. Question them as you implement — deviate if you have a stronger opinion.

- **Event field order: `(payload, eventId, timestamp)`** — arbitrary at this lesson but consequential at L6 (derived `Ord` sorts lexicographically by declaration order). If you want streams naturally sorted by *time*, put `timestamp` first.
- **`type Event` (alias) vs `newtype Event`** — I chose the alias to keep this lesson light. A `newtype` gives real type safety (you can't pass a random 3-tuple where an `Event` is expected). It's a fine instinct to upgrade to `newtype` — L2 makes the question moot by promoting to a record.
- **`timestamp :: String`** — kept stringly-typed for now. In real code this would be `UTCTime` from `Data.Time`. Stage 1 stays string-based to avoid introducing the `time` package this early.

---

## Done?

`runghc check.hs` prints `PASS ✓` → **move on to [Lesson 2](../02-adts-and-pattern-matching/README.md).**
