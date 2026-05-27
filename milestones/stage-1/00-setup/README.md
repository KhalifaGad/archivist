# Lesson 0 — Setup: A working Haskell environment

## Where you are

You may have never installed Haskell on this machine. That's the assumption.

## Learning goal

- Install and verify the Haskell toolchain via **GHCup**.
- Get comfortable with **GHCi**, the REPL, well enough to ask "what's the type of this?"
- Notice that types are checked *before* code runs — Haskell's defining trait.

## Delivery goal

A file `hello.hs` in this directory that compiles, runs, and prints `Hello, Archivist`.

---

## Concept warm-up (15–25 min)

### Install GHCup

GHCup is the version manager for the Haskell toolchain (GHC the compiler, Cabal the build tool, HLS the language server). On macOS / Linux:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

Accept defaults. **Restart your shell** when it's done (or `source` the env file the installer mentions).

Verify all three:

```sh
ghc --version       # expect 9.x
cabal --version     # expect 3.x
ghci --version
```

If any say "command not found", check the installer output — it tells you exactly which file to source from `~/.ghcup/env`.

### Editor with language server

Install the **Haskell** extension in VS Code (or the Haskell plugin in your editor of choice). It bundles **HLS** — Haskell Language Server — which gives you inline types, hovers, and errors. Open a `.hs` file and look at the bottom bar; you should see "Haskell" with no red.

### Five minutes in GHCi

Open a terminal and run `ghci`. Try each of these, one at a time:

```haskell
1 + 1
:t 5
:t "hello"
:t True
:t (5, "hi")
:t \x -> x + 1
let double x = x * 2
double 21
:t double
:q
```

Pay attention to `:t` — it asks "what is the type of this?". For `:t 5` you'll see `5 :: Num a => a`. Don't worry about `Num a =>` yet; read it as "5 is some kind of number". Typeclasses arrive in Lesson 6.

The shape `expression :: Type` is everywhere in Haskell. `::` is read **"has type"**.

---

## Build it

Create `hello.hs` in this directory with exactly one function — `main`. It must have type `IO ()` and print `Hello, Archivist`.

That's it. Two lines of code, more or less. Hint: `putStrLn` is the function that prints a `String` followed by a newline. Its type is `String -> IO ()`.

Once you've written it, **try both ways of running it**:

```sh
runghc hello.hs            # interpret and run — no binary produced
ghc hello.hs && ./hello    # compile and run a binary
```

Why both? `runghc` is convenient for scripts and tests. `ghc` produces a real binary — that's how production Haskell ships. Knowing both demystifies things.

---

## Verify

From this directory:

```sh
runghc check.hs
```

You should see:

```
PASS ✓ — hello.hs runs and prints "Hello, Archivist".
```

If you see `FAIL ✗`, the message tells you what's missing.

---

## Self-check

If you can answer these without looking, you're ready for Lesson 1.

1. What does `:t` do in GHCi?
2. What's the difference between `runghc` and `ghc`?
3. What does `String -> IO ()` mean in plain English?
4. Why does `main` have type `IO ()` and not just `()`?  *(A guess is fine. The full answer arrives in Lesson 3.)*
5. What command opens the REPL? What command quits it?

---

## Stretch

- Edit `hello.hs` so it tries to `putStrLn (1 + 1)`. What's the error? Read it carefully — it's your first real Haskell type error, and they're *verbose but accurate*.
- In GHCi, run `:i Int`. The output starts with `data Int = ...`. You've just looked at the actual definition of a built-in type. Haskell has very little magic — most "primitive" things are defined in plain Haskell.
- Try `:set +t` in GHCi. Now every expression you evaluate prints its inferred type too. Useful for early learning.

---

## Done?

`runghc check.hs` prints `PASS ✓` → **move on to [Lesson 1](../01-values-and-types/README.md).**
