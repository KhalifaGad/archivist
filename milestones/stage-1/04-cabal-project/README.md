# Lesson 4 — A real Cabal project

## Where you are

You have three loose `.hs` files: `Archivist.hs`, `Main.hs`, and a `check.hs` per lesson. That's fine for a tutorial. It's *not* how real Haskell ships.

This lesson is the **infrastructure lesson** of Stage 1. Less new Haskell syntax, more "how Haskell projects are actually organized." From here on, `cabal test` becomes your verification.

## Learning goal

- Understand what a **Cabal package** is — the `.cabal` file, dependencies, build targets
- Split a project into **modules** (one module per file, file path mirrors the module name)
- Wire up a **library**, an **executable**, and a **test-suite** in one package
- Use **Hspec** to write structured tests with clear failure messages
- Migrate the ad-hoc `check.hs` assertions from earlier lessons into real Hspec tests

## Delivery goal

A Cabal project living at the **repo root** (not inside this lesson directory — see the stage-1 README's "Project layout across lessons" section for the rationale). Structure:

```
<repo root>/
├── archivist.cabal
├── cabal.project              (optional, but recommended)
├── project_context.md         (already there)
├── src/
│   └── Archivist/
│       ├── Event.hs           module Archivist.Event
│       └── Stream.hs          module Archivist.Stream
├── app/
│   └── Main.hs                module Main
├── test/
│   ├── Spec.hs                Hspec entry point
│   └── Archivist/
│       ├── EventSpec.hs
│       └── StreamSpec.hs
└── milestones/                (this curriculum — already there)
    └── stage-1/
        └── 04-cabal-project/
            ├── README.md      (you are here)
            └── check.hs       (calls cabal test against the repo-root project)
```

Bring `Archivist.hs` (the record-based version from Lesson 2) and `Main.hs` (from Lesson 3) up to the repo root as the starting material — you'll split `Archivist.hs` into `Archivist.Event` and `Archivist.Stream` as part of this lesson.

When you run `cabal test` from the repo root, the suite goes green.

The `Archivist` module from Lesson 2 splits into two:

- `Archivist.Event` exports `Event`, `mkEvent`, accessor field selectors
- `Archivist.Stream` exports `Stream`, `SealStatus`, `emptyStream`, `appendToStream`, `eventCount`, and re-exports `Event` for convenience

---

## Concept warm-up (15 min)

### What is Cabal?

Cabal is two things:

1. **A package format.** A `.cabal` file describes your project: its name, version, dependencies, what to build (library / executable / tests), and where the source files live.
2. **A build tool.** The `cabal` command reads the file and does the work — fetches dependencies from Hackage, compiles modules, runs tests.

(There's also `stack`, a popular alternative. We use Cabal — it's the official tool and works well in 2024+.)

### Modules

Every `.hs` file is a module. The module's name must match the path under `src/` (or wherever the library's source root is):

- File: `src/Archivist/Event.hs`
- Module declaration: `module Archivist.Event where`

To use things from another module:

```haskell
import Archivist.Event (Event, mkEvent, payload)
```

You can import everything (`import Archivist.Event`), explicitly list what you want (recommended), hide things (`hiding (...)`), or qualify (`import qualified Archivist.Event as E` — then write `E.payload`).

### Hspec

Hspec is a test framework that reads like English. A spec file looks like:

```haskell
module Archivist.EventSpec where

import Test.Hspec
import Archivist.Event

spec :: Spec
spec = describe "Event" $ do
  it "exposes its payload via the field selector" $
    payload (mkEvent "p" "id" "t") `shouldBe` "p"
```

`describe` groups related tests. `it` is one test. `shouldBe` is the assertion (`x \`shouldBe\` y` fails with a clear message if `x /= y`).

The runner discovers all `*Spec` modules automatically if you use `hspec-discover` (we will).

---

## Build it

This is the longest section in the lesson. Take it in steps.

### Step 1 — Initialize the project

From the **repo root** (`cd` up three levels from this lesson directory):

```sh
cabal init --non-interactive \
  --package-name=archivist \
  --version=0.1.0.0 \
  --license=MIT \
  --lib --exe --tests \
  --main-is=Main.hs \
  --test-dir=test \
  --source-dir=src \
  --application-dir=app
```

This creates `archivist.cabal` plus skeleton source files. Open `archivist.cabal` and look at it.

You're going to **rewrite the cabal file** to look like the template below. Don't fight the auto-generated content — replace it.

### Step 2 — The `.cabal` file

Make `archivist.cabal` look like this (adjust the `cabal-version` line if your `cabal --version` is older than 3.0):

```cabal
cabal-version:      3.0
name:               archivist
version:            0.1.0.0
synopsis:           A typed, hierarchical, append-only event store.
license:            MIT
author:             Khalifa
build-type:         Simple

common warnings
    ghc-options:    -Wall -Wno-unused-imports

library
    import:           warnings
    exposed-modules:  Archivist.Event
                    , Archivist.Stream
    hs-source-dirs:   src
    build-depends:    base ^>=4.18
    default-language: Haskell2010

executable archivist-demo
    import:           warnings
    main-is:          Main.hs
    hs-source-dirs:   app
    build-depends:    base ^>=4.18
                    , archivist
    default-language: Haskell2010

test-suite archivist-test
    import:           warnings
    type:             exitcode-stdio-1.0
    hs-source-dirs:   test
    main-is:          Spec.hs
    other-modules:    Archivist.EventSpec
                    , Archivist.StreamSpec
    build-depends:    base ^>=4.18
                    , archivist
                    , hspec ^>=2.11
    build-tool-depends: hspec-discover:hspec-discover ^>=2.11
    default-language: Haskell2010
```

The `base ^>=4.18` constraint matches GHC 9.6+. If `cabal build` complains, change it to whatever `ghc --version` suggests (`base ^>=4.17` for GHC 9.4, etc.). Or just write `base >=4.16 && <5` to be loose for now.

### Step 3 — Split the modules

Create `src/Archivist/Event.hs`:

```haskell
module Archivist.Event
  ( Event (..)
  , mkEvent
  ) where

data Event = Event
  { payload   :: String
  , eventId   :: String
  , timestamp :: String
  } deriving (Show, Eq)

mkEvent :: String -> String -> String -> Event
mkEvent p i t = Event { payload = p, eventId = i, timestamp = t }
```

`Event (..)` in the export list means "export the type `Event` and all its constructors and fields." Without `(..)`, you'd only export the name `Event` and consumers couldn't construct or pattern-match.

Create `src/Archivist/Stream.hs`:

```haskell
module Archivist.Stream
  ( Stream (..)
  , SealStatus (..)
  , emptyStream
  , appendToStream
  , eventCount
  , module Archivist.Event
  ) where

import Archivist.Event

data Stream = Stream
  { streamId :: String
  , events   :: [Event]
  } deriving (Show, Eq)

data SealStatus = Unsigned | Sealed deriving (Show, Eq)

emptyStream :: String -> Stream
emptyStream sid = Stream { streamId = sid, events = [] }

appendToStream :: Event -> Stream -> Stream
appendToStream e s = s { events = events s ++ [e] }

eventCount :: Stream -> Int
eventCount = length . events
```

The `module Archivist.Event` re-export in the export list means "anyone who imports `Archivist.Stream` also gets everything `Archivist.Event` exports." Convenience for callers.

### Step 4 — The executable

Create `app/Main.hs`:

```haskell
module Main where

import Archivist.Stream

main :: IO ()
main = do
  let s = appendToStream (mkEvent "payment-received" "evt-2" "t2")
        $ appendToStream (mkEvent "order-placed"     "evt-1" "t1")
        $ emptyStream "orders"
  putStrLn ("Stream: " ++ streamId s)
  mapM_ (\e -> putStrLn (eventId e ++ ": " ++ payload e)) (events s)
```

Run it:

```sh
cabal run archivist-demo
```

### Step 5 — The test suite

Create `test/Spec.hs` — this is the **entry point**. It's exactly one line:

```haskell
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
```

That pragma tells GHC to preprocess this file with `hspec-discover`, which auto-generates a `main` that runs every `*Spec` module it finds.

Create `test/Archivist/EventSpec.hs`:

```haskell
module Archivist.EventSpec (spec) where

import Test.Hspec
import Archivist.Event

spec :: Spec
spec = describe "Archivist.Event" $ do
  let e = mkEvent "order-placed" "evt-1" "2024-01-01"

  it "exposes the payload field"   $ payload e   `shouldBe` "order-placed"
  it "exposes the eventId field"   $ eventId e   `shouldBe` "evt-1"
  it "exposes the timestamp field" $ timestamp e `shouldBe` "2024-01-01"

  it "compares equal events with ==" $
    mkEvent "p" "i" "t" `shouldBe` mkEvent "p" "i" "t"

  it "compares unequal events with /=" $
    mkEvent "a" "i" "t" `shouldNotBe` mkEvent "b" "i" "t"
```

Create `test/Archivist/StreamSpec.hs`:

```haskell
module Archivist.StreamSpec (spec) where

import Test.Hspec
import Archivist.Stream

spec :: Spec
spec = describe "Archivist.Stream" $ do
  let e1 = mkEvent "p1" "evt-1" "t1"
      e2 = mkEvent "p2" "evt-2" "t2"

  it "starts a stream with no events" $
    events (emptyStream "orders") `shouldBe` []

  it "remembers the streamId" $
    streamId (emptyStream "orders") `shouldBe` "orders"

  it "appends to the end of the log" $
    events (appendToStream e2 (appendToStream e1 (emptyStream "s")))
      `shouldBe` [e1, e2]

  it "preserves the streamId on append" $
    streamId (appendToStream e1 (emptyStream "s")) `shouldBe` "s"

  it "counts events" $
    eventCount (appendToStream e1 (appendToStream e2 (emptyStream "s")))
      `shouldBe` 2

  it "distinguishes Sealed from Unsigned" $
    Sealed `shouldNotBe` Unsigned
```

### Step 6 — Build and test

```sh
cabal build
cabal test
```

If the build fails on dependency resolution, run `cabal update` first to refresh the package index. If `hspec-discover` can't be found, double-check the `build-tool-depends` line in your `.cabal` file.

---

## Verify

From this lesson directory:

```sh
runghc check.hs
```

…which `cd`s up to the repo root, runs `cabal test`, and reports.

A green `cabal test` is the real signal. From Lesson 5 onward, that's all you need to run.

---

## Self-check

1. What's the difference between a **library**, an **executable**, and a **test-suite** stanza in a `.cabal` file?
2. What does `Event (..)` mean in an export list? What changes if you drop the `(..)`?
3. Why is `test/Spec.hs` just a one-line pragma? What does `hspec-discover` do?
4. Why is `app/Main.hs` not in the library?
5. If you wanted to use `Archivist.Stream` from another package one day, what would you need to do? (Hint: it's the line where the library exports the module.)

---

## Stretch

- Add a `-Werror` line to the `warnings` common section. Now warnings break the build. Are your modules clean?
- Run `cabal repl` — it's a GHCi that already knows about your modules. Try `events (emptyStream "demo")`.
- Add `cabal-fmt` or `fourmolu` (a formatter) and run it on `src/`. Consistent style matters when projects grow.
- Read `cabal list-bin archivist-demo`. What does that command tell you?

---

## Design choices baked into this lesson

- **Module hierarchy `Archivist.Event` / `Archivist.Stream`** — the `Archivist.` prefix is convention. Flat names (`Event`, `Stream`) work too, but namespaced modules play better with growing projects and IDE search.
- **`hspec ^>=2.11` version pin** — conservative. If Cabal can't resolve dependencies, loosen to `hspec >=2.10 && <3`.
- **`base ^>=4.18`** — that's GHC 9.6. If your `ghc --version` is older, change it (GHC 9.4 = `base ^>=4.17`; GHC 9.2 = `base ^>=4.16`). Or use the loose `base >=4.16 && <5`.
- **`module Archivist.Event` re-exported from `Archivist.Stream`** — convenience over explicitness. Some style guides discourage transitive re-exports because they hide which module *really* defines a name. I included it because tests stay shorter. Drop the re-export if you prefer explicit imports.
- **`-Wno-unused-imports` in the warnings common stanza** — I silenced this one warning. As the project grows you'll have moments where you intentionally over-import to keep diff churn down. Re-enable once code stabilizes.
- **`exitcode-stdio-1.0` test-suite type** — the standard. `detailed-0.9` exists but is rarely used.

---

## Done?

`cabal test` is green → **Act I complete.** You now have a real Haskell project with passing tests.

The next run will continue with Act II: `Maybe`/`Either`, typeclasses, folds, phantom types, and the GADT showpiece. Tell Claude when you're ready and we'll write Run 2.
