# Lesson 3 — `IO` and the pure/effectful split

## Where you are

You have `Archivist.hs` with `Event`, `Stream`, `appendToStream`. Everything is *pure*: functions take values and return values. Nothing prints, nothing reads input, nothing touches the world.

Programs that don't touch the world aren't useful. Time to fix that — carefully.

## Learning goal

- Understand why Haskell separates **pure** computations from **effectful** ones using the `IO` type
- Read and write `do` notation for sequencing IO actions
- Use `putStrLn`, `print`, `getLine`, `readFile`
- Internalize the idea: an `IO a` is a *plan* to produce an `a`. Running the program executes the plan.

## Delivery goal

A file `Main.hs` in this directory that:

1. Imports `Archivist`
2. Defines `main :: IO ()` which:
   - Builds a `Stream` called `"orders"` by appending at least two events
   - Prints the stream id
   - Prints each event's `eventId` and `payload` on its own line, in order
3. Specifically, the output must contain the literal strings `order-placed` and `payment-received` (the verification checks for these)

Copy `Archivist.hs` from Lesson 2 into this directory as your starting point. **Do not modify it.** The whole point is that pure code stays pure; `Main.hs` is where IO lives.

---

## Concept warm-up (20 min)

### The two-language intuition

Haskell behaves like **two languages stacked**:

- **Pure expressions:** values that don't depend on the outside world. `1 + 1`, `mkEvent "a" "b" "c"`, `length [1,2,3]`. Calling them with the same arguments always gives the same result. No surprises.
- **IO actions:** things that interact with the world. `putStrLn "hi"`, `getLine`, `readFile "log.txt"`. Their type is `IO a` — read as "an action that, when executed, produces an `a`".

The two are kept separate by the type system. A pure function *cannot* call `putStrLn` — the type system won't let it. This is on purpose: it means anything *not* in `IO` is provably free of side effects.

### `IO a` is a value, not an execution

This is the part that trips people up:

```haskell
let action = putStrLn "hello"
:t action
-- action :: IO ()
```

`action` is just a value of type `IO ()`. It hasn't *done* anything yet. The runtime only executes it when it ends up as part of `main`.

This is why you can build IO actions, pass them around, store them in lists, and combine them — they're just data describing what to do.

### `do` notation

`do` notation is sugar for sequencing IO actions. Try this in GHCi:

```haskell
:{
let prog = do
      putStrLn "What's your name?"
      n <- getLine
      putStrLn ("Hello, " ++ n)
:}
:t prog
-- prog :: IO ()
prog            -- runs it
```

Rules of `do` blocks:

- Each line is an IO action.
- `x <- something` runs the action `something :: IO a` and binds the resulting `a` to `x`.
- A line without `<-` is an action whose result you don't care about (typically `IO ()`).
- The last line is the result of the whole `do` block.

You'll often want to put a **pure value** in a `do` block — for that, use `pure` (or `return`, which is the same thing in IO):

```haskell
:{
let prog2 = do
      putStrLn "Computing..."
      let x = 1 + 2          -- pure binding inside do — note: `let`, no `<-`
      pure x
:}
:t prog2
-- prog2 :: IO Int
```

Notice two ways to bind:

- `x <- ioAction` — runs the action, binds its result
- `let x = pureExpr` — pure binding, no action involved

---

## Read the tests first

Open `check.hs`. It runs your `Main.hs` via `runghc`, captures stdout, and looks for specific substrings: `order-placed` and `payment-received`. So your hardcoded events **must use those exact payload strings**.

---

## Build it

`Main.hs` skeleton:

```haskell
module Main where

import Archivist

main :: IO ()
main = do
  let e1 = mkEvent "order-placed"     "evt-1" "2024-01-01T10:00:00Z"
      e2 = mkEvent "payment-received" "evt-2" "2024-01-01T10:05:00Z"
      s  = appendToStream e2 (appendToStream e1 (emptyStream "orders"))
  -- TODO: print the stream id, then each event's id and payload
  pure ()
```

Fill in the `TODO`. Suggestions:

- `putStrLn ("Stream: " ++ streamId s)` to print the id
- To iterate the events, use `mapM_`:
  ```haskell
  mapM_ printEvent (events s)
  ```
  with a helper:
  ```haskell
  printEvent :: Event -> IO ()
  printEvent e = putStrLn (eventId e ++ ": " ++ payload e)
  ```

`mapM_` runs an IO action for each element of a list and discards the results. Read its type with `:t mapM_` in GHCi — `(a -> IO b) -> [a] -> IO ()`. The trailing underscore means "throw away the results".

Run it:

```sh
runghc Main.hs
```

You should see something like:

```
Stream: orders
evt-1: order-placed
evt-2: payment-received
```

---

## Verify

```sh
runghc check.hs
```

The verification runs `Main.hs` as a subprocess and checks that the output contains the right substrings.

---

## Self-check

1. What does `IO a` mean in plain English?
2. Why can't a pure function call `putStrLn`?
3. What's the difference between `x <- action` and `let x = expr` inside a `do` block?
4. What does `mapM_` do? What does the underscore in its name signify?
5. Suppose I write `let p = putStrLn "hi"` at the top of `main`. Does anything print? Why or why not?

---

## Stretch

- Add a third event whose payload is read from stdin via `getLine`. Pipe input in: `echo "shipped" | runghc Main.hs`.
- Try `print s` (where `s` is your stream). What gets printed and why? (Hint: `print` is `putStrLn . show`.)
- Try writing the stream to a file with `writeFile "stream.txt" (show s)`. Open the file. You've just done your first "persistence" — except the file format is Haskell's `show` output, which isn't a real serialization. Lesson 11 replaces this with SQLite.

---

## Design choices baked into this lesson

- **Print format `<id>: <payload>`** — arbitrary. The verification only looks for the substrings `order-placed` and `payment-received` and their relative order. Format the rest however you like.
- **Two hardcoded events in `main`** — fine for now. If you'd rather read events from `stdin`, command-line args, or a file, the test still passes as long as the expected substrings appear in order. (`getLine` is fine; `getArgs` from `System.Environment` is fine too.)
- **No interaction (yet) between `Main.hs` and the stream after building it** — the only thing `main` does is print. Real CLIs would also accept commands. We stay tiny on purpose; the executable grows in L4 and L13.

---

## Done?

`runghc check.hs` prints `PASS ✓` → **move on to [Lesson 4](../04-cabal-project/README.md).**
