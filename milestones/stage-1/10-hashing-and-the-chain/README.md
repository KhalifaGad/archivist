# Lesson 10 — Real cryptographic hashing and the chain

## Where you are

`EventStream` is a GADT. `sealStream` exists but stuffs empty strings into the hashes. `verify` lies and returns `True`. Time to fix both.

Welcome to **Act III — *It survives a crash.*** Three lessons of durability + proof, then the capstone.

## Learning goal

- Understand the contract a **cryptographic hash function** offers: deterministic, fixed-size output, collision-resistant, infeasible to reverse
- Use the `cryptonite` library to compute SHA-256 hashes
- Understand a **hash chain**: each link includes the previous link's hash, so any tampering invalidates everything downstream
- Implement `sealStream` and `verify` for real

## Delivery goal

1. New module `Archivist.Hash` with:
    - `type Hash = String` (hex-encoded SHA-256, 64 characters)
    - `emptyHash :: Hash` — the genesis "previous hash" used for the first event in a chain (empty string `""`)
    - `hashEvent :: Event String -> Hash -> Hash` — combines an event's serialized form with the previous hash and returns the new hash
2. Update `Archivist.Stream`:
    - `SealedEvent`'s `sealedHash`/`prevHash` are now real `Hash` values (still `String`-typed)
    - `sealStream` computes the chain: first event hashes against `emptyHash`, each subsequent event hashes against the previous event's `sealedHash`
    - `verify :: EventStream e Sealed -> Bool` recomputes the chain and returns `True` iff every stored hash matches
3. Tests prove tamper-evidence: mutating any event invalidates `verify`.

---

## Concept warm-up (25 min)

### What a hash function actually does

A cryptographic hash function takes bytes in and gives a fixed-size digest out. For SHA-256, the digest is always 32 bytes (256 bits), conventionally rendered as 64 hex characters.

Three properties matter to us:

1. **Deterministic.** Same input bytes → same output digest, forever. No randomness.
2. **Collision-resistant.** Finding two different inputs that produce the same digest is infeasible. (This is what gives us tamper-evidence.)
3. **One-way.** Given a digest, you cannot recover the input. (We don't need this property for sealing, but it's part of the contract.)

What a hash function is **not**:

- It is not encryption. There's no key, no way to "decrypt".
- It is not random. Same input always gives the same output.
- It does not include time. Two identical events produce identical hashes.

### Hash chains

If each event includes the previous event's hash in its own hash input, the result is a **chain**:

```
event 1 → hash 1 = H( event 1  || "" )
event 2 → hash 2 = H( event 2  || hash 1 )
event 3 → hash 3 = H( event 3  || hash 2 )
event 4 → hash 4 = H( event 4  || hash 3 )
```

`||` means concatenation; `""` (empty string) is the genesis "previous hash" for the first event.

Tamper with event 2 → its hash changes → event 3's hash no longer matches its `prevHash` link → verify fails. Tamper with the *hash field itself* of event 2 → the chain link from event 3 still points to the old expected hash → verify fails. There is no edit you can make to a single event that doesn't cascade detectably.

This is the **tamper-evident** property. Not tamper-*proof* — someone with write access can still rewrite *every* downstream event's hash. But they cannot do it silently, because they'd have to know about the chain. And in real deployments, periodic checkpoints (publishing a current hash to an external system) make full rewrite detectable too. That's a Stage 3 concern.

### Hashing a structured value

You cannot directly hash an `Event` — hash functions consume bytes. You first **serialize** the event to a canonical byte string, then hash it. The serialization must be deterministic — same event, same bytes, always.

The simplest deterministic serialization: concatenate the fields with a separator the data cannot contain:

```haskell
serialize :: Event String -> String -> String
serialize e prev = payload e ++ "\0" ++ eventId e ++ "\0" ++ timestamp e ++ "\0" ++ prev
```

`\0` (NUL) is a fine separator for `String` fields because text data normally doesn't contain it. In real systems, JSON or `binary`-serialized bytes are the canonical choice — both are bijective (no two different events ever produce the same bytes). We use NUL-separated strings for Stage 1 simplicity.

### Using `cryptonite`

```haskell
{-# LANGUAGE TypeApplications #-}
import Crypto.Hash (Digest, SHA256, hash)
import qualified Data.ByteString.Char8 as BS

-- A Digest SHA256 has a Show instance that prints the hex string:
let d = hash @SHA256 (BS.pack "hello")
show d
-- "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
```

`hash @SHA256` is a type application — it tells the polymorphic `hash :: HashAlgorithm a => ByteString -> Digest a` *which* algorithm to use. Without it, GHC wouldn't know whether you wanted SHA-256, SHA-512, BLAKE2, etc.

Add `cryptonite`, `bytestring`, and (optionally) `memory` to your library's `build-depends` in `archivist.cabal`.

---

## Read the tests first

Update `test/Archivist/SealSpec.hs`:

```haskell
  describe "sealStream + verify (real hashing)" $ do
    let e1 = mkEvent "p1" "evt-1" "t1" :: Event String
        e2 = mkEvent "p2" "evt-2" "t2"
        e3 = mkEvent "p3" "evt-3" "t3"
        unsigned = appendUnsigned e3
                 . appendUnsigned e2
                 . appendUnsigned e1
                 $ emptyUnsigned "orders"
        sealed = sealStream unsigned

    it "computes a non-empty 64-char hex hash for each event" $ do
      let hs = map sealedHash (sealedEvents sealed)
      length hs `shouldBe` 3
      mapM_ (\h -> length h `shouldBe` 64) hs

    it "links the chain: each prevHash equals the previous sealedHash" $ do
      let evs = sealedEvents sealed
      case evs of
        [a, b, c] -> do
          prevHash a `shouldBe` emptyHash       -- genesis
          prevHash b `shouldBe` sealedHash a
          prevHash c `shouldBe` sealedHash b
        _ -> expectationFailure "expected three sealed events"

    it "verify returns True on an untampered sealed stream" $
      verify sealed `shouldBe` True

    it "verify returns False if a payload is tampered with" $ do
      let tampered = case sealed of
            SealedStream sid evs -> SealedStream sid (tamperFirst evs)
          tamperFirst (se:rest) =
            se { sealedEvent = (sealedEvent se) { payload = "EVIL" } } : rest
          tamperFirst [] = []
      verify tampered `shouldBe` False

    it "verify returns False if events are reordered" $ do
      let reordered = case sealed of
            SealedStream sid evs -> SealedStream sid (reverse evs)
      verify reordered `shouldBe` False
```

This test reaches into the GADT constructors directly (`SealedStream sid evs`) — that's fine *inside the package*, because the data constructor is in scope. End users would not be able to do this.

Note: this requires temporarily exposing the `SealedStream` constructor to tests. Two ways to handle that:

- **Option A** — Add `SealedStream (..)` to the export list of `Archivist.Stream` (visible to everyone). Honest but leaks.
- **Option B** — Create an `Archivist.Stream.Internal` module that re-exports the constructors, and import it only from tests. Conventional in real Haskell libraries.

I picked Option A in the lesson body for brevity; do Option B if you're feeling fancy.

---

## Build it

### `Archivist.Hash`

Create `src/Archivist/Hash.hs`:

```haskell
{-# LANGUAGE TypeApplications #-}
module Archivist.Hash
  ( Hash
  , emptyHash
  , hashEvent
  ) where

import Crypto.Hash (Digest, SHA256, hash)
import qualified Data.ByteString.Char8 as BS
import Archivist.Event

type Hash = String  -- 64-char hex representation of a SHA-256 digest

emptyHash :: Hash
emptyHash = ""      -- genesis previous-hash

hashEvent :: Event String -> Hash -> Hash
hashEvent e prev = show (hash @SHA256 input)
  where
    input :: BS.ByteString
    input = BS.pack $ payload e ++ "\NUL" ++ eventId e ++ "\NUL"
                  ++ timestamp e ++ "\NUL" ++ prev
```

The `show` on a `Digest SHA256` gives the lowercase hex string. Good enough.

Register `Archivist.Hash` in `archivist.cabal`'s `exposed-modules`.

### Update `sealStream`

In `src/Archivist/Stream.hs`:

```haskell
import Archivist.Hash

sealStream :: EventStream String Unsigned -> EventStream String Sealed
sealStream (UnsignedStream sid es) = SealedStream sid (link emptyHash es)
  where
    link _ []     = []
    link prev (e:rest) =
      let h = hashEvent e prev
          se = SealedEvent { sealedEvent = e, sealedHash = h, prevHash = prev }
      in se : link h rest
```

We've now specialized `sealStream` to `EventStream String _` because `hashEvent` needs a `String` payload. Generalizing to arbitrary payload types requires a `Serializable` typeclass — a Stretch.

### Implement `verify`

```haskell
verify :: EventStream String Sealed -> Bool
verify (SealedStream _ es) = go emptyHash es
  where
    go _ [] = True
    go prev (se : rest) =
      prevHash se == prev
      && sealedHash se == hashEvent (sealedEvent se) prev
      && go (sealedHash se) rest
```

Notice the *two* checks per event:
1. The stored `prevHash` field equals what we expect from the chain so far
2. The stored `sealedHash` equals what we compute now from the event + prev

Both must hold. Either alone leaves a hole — the first guards against reordering, the second against payload tampering.

### Update the cabal file

`archivist.cabal`'s library `build-depends:`:

```cabal
    build-depends:    base ^>=4.18
                    , bytestring ^>=0.11
                    , cryptonite ^>=0.30
```

Run `cabal build`. The first time will pull cryptonite from Hackage — takes a minute.

---

## Verify

```sh
runghc check.hs
```

Bonus exercise: open `cabal repl`, build a small sealed stream, print its hashes. Then in a separate REPL session do the same. The hashes should match exactly — that's determinism, and that's the whole point.

---

## Design choices baked into this lesson

- **SHA-256 over BLAKE2 / BLAKE3** — SHA-256 is ubiquitous, well-known, supported everywhere. BLAKE2b is faster and modern; BLAKE3 is faster still but newer. The project doc says "TBD: BLAKE3 or SHA-256". Switching algorithms is a one-line change (`hash @SHA256` → `hash @BLAKE2b_256`) — defer the decision until L13's reflection.
- **`Hash = String` (hex)** — clean for tests, SQLite-friendly in L11, prints nicely. The alternative is `ByteString` (raw 32 bytes). `String` doubles storage and slows things slightly. Production code uses `ByteString`; we choose readability.
- **Genesis hash is `""`** — empty string. Alternative: 64 zero characters (`"00…0"`) to keep all hashes the same length. I picked empty because the *fact* of being empty signals "this is the start of the chain" unambiguously. Pick the other if you prefer uniform widths.
- **Field separator `\NUL`** — fine for text fields, breaks if a field ever contains literal NUL bytes. Production answer: length-prefix each field, or serialize to JSON/CBOR. We accept the simplification for Stage 1.
- **`cryptonite` package** — actively maintained but old; `crypton` is the modern fork with the same API. If `cryptonite` fails to build on a recent GHC, switch to `crypton` — the imports and call sites are identical.
- **`sealStream` is specialized to `EventStream String Unsigned`** — generalizing requires a `class Serializable e where serialize :: e -> ByteString` typeclass. Honest and easy; left as a Stretch so this lesson stays about the *chain*, not abstraction.
- **`SealedStream` constructor exported (Option A)** — for test convenience. The clean alternative is an `Archivist.Stream.Internal` module — see the *Read the tests first* section.

---

## Self-check

1. What three properties of a hash function matter for tamper-evidence?
2. Why does `verify` check both `prevHash` *and* `sealedHash` for each event? What attack does each one block?
3. If you reordered two events in a sealed stream, would the stored `sealedHash` of the first event still be the original (correct) value? Where exactly does the chain break?
4. What changes about `sealStream` if events become parameterized by arbitrary payload types (not just `String`)?
5. The project context calls the upgrade path "Unsigned → Sealed allowed; Sealed → Unsigned not allowed." Why is the reverse direction *fundamentally impossible* once a stream is sealed?

---

## Stretch

- Introduce `class Serializable e where serialize :: e -> ByteString` with an instance for `String`. Generalize `hashEvent`, `sealStream`, and `verify` to work over any serializable payload.
- Add `appendSealed :: Event String -> EventStream String Sealed -> EventStream String Sealed` that takes the existing stream, computes the new event's hash against the last sealedHash, and returns the new sealed stream. Verify still passes after appendSealed.
- Implement the `UnsignedLegacy` upgrade path described in `project_context.md`: a function `upgradeStream :: EventStream String Unsigned -> EventStream String Sealed` that wraps old events as legacy (no hash) and starts the chain at the *first new* event. Update `verify` to skip the legacy prefix.
- Read about Merkle trees. SHA-chains prove *sequential* integrity; Merkle trees prove *batched* integrity in log-depth. Stage 3 territory.

---

## Done?

`cabal test` is green → **move on to [Lesson 11](../11-sqlite-persistence/README.md).**
