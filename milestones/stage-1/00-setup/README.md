# Lesson 0 — Setup: A working Haskell environment

## Where you are

You may have never installed Haskell on this machine. That's the assumption.

## Learning goal

- Get the Haskell toolchain working — GHC, Cabal, HLS, and ghcup
- Get comfortable with **GHCi**, the REPL, well enough to ask "what's the type of this?"
- Notice that types are checked *before* code runs — Haskell's defining trait

## Delivery goal

A file `hello.hs` in this directory that compiles, runs, and prints `Hello, Archivist`.

---

## Step 1 — Install the toolchain

Toolchain installation is a separate document because it has enough edge cases (existing installs, old GHC versions, macOS + Homebrew LLVM, installing on an external drive) to deserve its own room.

➡️ **Follow [INSTALL.md](INSTALL.md), then come back here.**

You're done with Step 1 when this is true in a fresh terminal:

```sh
ghc --version       # prints 9.6.x
cabal --version     # prints 3.10 or later
```

---

## Step 2 — Five minutes in GHCi

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

## Design choices baked into this lesson

- **GHC 9.6.7 over 9.6.6 or 9.8/9.10** — 9.6.x matches the `base ^>=4.18` constraint in later cabal files. 9.6.7 specifically has *prebuilt* HLS binaries; 9.6.6 doesn't (HLS would have to be compiled from source, which takes ages). Other 9.6.x patch versions with prebuilt HLS are fine — check `ghcup list` for the current set.
- **ghcup over Stack** — the official ecosystem standard since ~2020. Stack still works but isn't used in this roadmap.
- **HLS recommended over manually picked HLS** — `ghcup install hls recommended` resolves to whatever HLS the project currently endorses for your GHC. Drift-resistant.

---

## Done?

`runghc check.hs` prints `PASS ✓` → **move on to [Lesson 1](../01-values-and-types/README.md).**
