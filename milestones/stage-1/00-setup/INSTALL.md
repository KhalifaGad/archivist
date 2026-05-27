# Installing the Haskell toolchain

This is the long version of the install. The lesson's [README.md](README.md) sends you here to get GHC, Cabal, HLS, and ghcup working. When everything below verifies green, return to the README and continue with the lesson.

## What you're installing

| Tool | What it does | Where it goes |
|---|---|---|
| **ghcup** | Version manager for the next three (like `nvm` / `rustup` / `pyenv`) | `~/.ghcup/bin/ghcup` (or `<prefix>/.ghcup/bin/ghcup` if relocated) |
| **GHC** | The compiler (`ghc`, `ghci`, `runghc`) | `~/.ghcup/ghc/<version>/` |
| **Cabal** | Build tool + package manager (`cabal build`, `cabal test`) | `~/.ghcup/bin/cabal` |
| **HLS** | Haskell Language Server — your editor's brain | `~/.ghcup/hls/<version>/` |

End-state you're aiming for:

```sh
ghc --version       # 9.6.7 (or any 9.6.x — see "Why 9.6.x?" below)
cabal --version     # 3.10 or later
ghcup --version     # 0.2.x
```

> **Why 9.6.x?** The roadmap's cabal files target `base ^>=4.18`, which is GHC 9.6's base. 9.6.7 specifically has prebuilt HLS binaries available; 9.6.6 doesn't and requires HLS to compile from source. We default to **9.6.7** for that reason.

> **Multiple GHCs are fine.** ghcup can manage several versions side-by-side. Switching is a single command (`ghcup set ghc <version>`).

---

## Step 1 — Find out what's already installed

Installing a Haskell extension in VS Code / Cursor sometimes auto-installs GHC and HLS in the background, often pinned to an older version (e.g. GHC 8.10.7). Before installing anything, find out what's already on your machine:

```sh
which ghcup            # where is the version manager? (or "not found")
ghcup --version        # what version of ghcup, if any?
which ghc              # where is the compiler being picked up from?
ghc --version          # what compiler version?
cabal --version        # what cabal version?
```

You'll fall into one of three cases. Jump to the matching step.

| Symptom | Case | Go to |
|---|---|---|
| `ghc --version` reports **9.4, 9.6, or 9.8**, and `ghcup --version` works | A — Good to go | Step 4 (Editor) |
| `ghcup --version` works but `ghc --version` reports **8.x** (old) | B — Upgrade GHC via ghcup | Step 3 |
| `ghcup: command not found` (you have GHC from another source, or nothing at all) | C — Install ghcup fresh | Step 2 |

---

## Step 2 — Case C: install ghcup from scratch

On macOS / Linux:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

Accept defaults. The installer will ask whether to install HLS — say **yes**; you need it for the editor.

When the installer finishes:

1. **Restart your shell** (close and reopen the terminal), or `source ~/.ghcup/env` in the current one.
2. Verify:

   ```sh
   ghcup --version
   ghc --version       # expect 9.x
   cabal --version     # expect 3.x
   ```

If any "command not found" survives after restarting the shell, `~/.ghcup/bin` isn't on `PATH`. Open `~/.zshrc` (or `~/.bashrc`) — there should be a line like:

```sh
[ -f "$HOME/.ghcup/env" ] && source "$HOME/.ghcup/env"
```

Add it if missing. Restart the shell.

> **macOS users:** before continuing, read the [**macOS C/C++ gotcha**](#macos-cc-gotcha-homebrew-llvm-on-path) section below. If you have Homebrew LLVM installed (you do if `which clang` reports anything under `/opt/homebrew/opt/llvm/`), GHC's configure step will fail with a `<wchar.h>` or `<pthread.h>` error during installation. Apply the fix *first*, then proceed.

Once `ghc --version` shows 9.x, **skip to Step 4 (Editor)**.

---

## Step 3 — Case B: upgrade an old GHC via ghcup

You have ghcup but `ghc --version` says 8.x.

See what's installed and what's available:

```sh
ghcup list
```

The rows tagged `set` are what your shortcuts currently resolve to.

Install the recommended versions of all three tools:

```sh
ghcup install ghc 9.6.7
ghcup set ghc 9.6.7

ghcup install cabal recommended
ghcup set cabal recommended

ghcup install hls recommended
ghcup set hls recommended
```

> **macOS users:** if the `ghcup install ghc` step fails with a `<wchar.h>`, `<pthread.h>`, or `<iostream>` error, see the [**macOS C/C++ gotcha**](#macos-cc-gotcha-homebrew-llvm-on-path) section below. Fix that, then retry the install.

Verify:

```sh
ghc --version       # should now be 9.6.x
cabal --version     # 3.10+
which ghc           # should resolve to ~/.ghcup/bin/ghc, not somewhere else
```

If `which ghc` still points at the old install (often `/usr/local/bin/ghc` or a Homebrew path), your shell's `PATH` has `~/.ghcup/bin` *after* the older location. Move the ghcup env source line to the **end** of your `.zshrc` / `.bashrc`. Restart the shell.

Prefer a GUI? `ghcup tui` opens an interactive picker — `i` to install, `s` to set as default.

You can leave the old 8.10 installed; it stays available via `ghcup set ghc 8.10.7` if you ever need it.

---

## macOS C/C++ gotcha: Homebrew LLVM on PATH

If you've ever run `brew install llvm` (or have it as a dependency of something else), your `PATH` likely contains `/opt/homebrew/opt/llvm/bin`. Homebrew's clang doesn't know where macOS's SDK headers live, so:

```sh
echo '#include <iostream>' | clang++ -x c++ -E - >/dev/null
# fatal error: 'wchar.h' file not found
# fatal error: 'pthread.h' file not found
```

When GHC's configure step calls `clang++` to check the C++ environment, it picks the broken Homebrew clang and fails. Three things fix this:

### Permanent fix (recommended) — add to `~/.zshrc`

```sh
# Tell C/C++ compilers where macOS SDK headers are. Safe to set globally —
# Apple tooling expects SDKROOT in non-Xcode shells; tools that ignore it
# are unaffected.
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null)}"

# Force ghcup (and any GHC it installs) to build against Apple's Clang, not
# Homebrew LLVM. Scoped to `ghcup` invocations only — other tools still
# resolve cc/c++ via PATH normally.
alias ghcup='CC=/usr/bin/clang CXX=/usr/bin/clang++ command ghcup'
```

Restart your shell. Future `ghcup install ghc <whatever>` calls "just work" with no env-juggling.

### Why this is scoped to Haskell

- `SDKROOT` set globally is benign — it's just a string env var. Tools that look for it work better; tools that don't are unaffected.
- `CC` / `CXX` are **not** exported globally; they're injected only when you call `ghcup`, via the alias. Your Go/Rust/Node/Ruby/Homebrew toolchains never see them.
- Once GHC is installed with Apple Clang, GHC records the absolute path of `/usr/bin/clang` in its internal `settings` file. Every subsequent `cabal build` uses Apple Clang automatically, no env vars needed.

### Verify the fix worked

In a fresh shell:

```sh
echo "$SDKROOT"                                                              # should print a path
echo '#include <iostream>' | clang++ -x c++ -E - >/dev/null && echo OK       # should print OK
```

If both look good, your `ghcup install ghc 9.6.7` will succeed.

### Prerequisite: Xcode Command Line Tools

`SDKROOT` only works if Xcode Command Line Tools are installed. Run:

```sh
xcode-select -p     # should print /Library/Developer/CommandLineTools
```

If it errors, run `xcode-select --install`, click **Install** in the GUI dialog that appears, and wait for it to finish (~500 MB, 5–15 min). Then verify with the command above.

---

## Optional: install on an external drive

If your internal disk is tight (Haskell wants ~4–5 GB for the toolchain plus more as your Cabal store grows), you can put the entire toolchain on an external drive. Requirements:

- **External must be APFS or HFS+** (FAT/exFAT break symlinks and Unix permissions). Format with Disk Utility → Erase → APFS if needed.
- **External must stay plugged in** when you do Haskell work. The rest of your dev environment is unaffected if you unplug — only Haskell commands stop resolving.
- **Use an SSD over USB-C / Thunderbolt.** Spinning HDD or slow USB stick → painful `cabal build` times.

### Setup (replace `MYDRIVE` with your external's actual mount name)

Add these to `~/.zshrc` **before** the existing ghcup env source line:

```sh
export GHCUP_INSTALL_BASE_PREFIX="/Volumes/MYDRIVE/haskell"
export CABAL_DIR="/Volumes/MYDRIVE/haskell/cabal"
```

Update the ghcup env source line at the bottom of `.zshrc` to point at the external:

```sh
[ -f "/Volumes/MYDRIVE/haskell/.ghcup/env" ] && source "/Volumes/MYDRIVE/haskell/.ghcup/env"
```

Restart the shell. Run the standard ghcup installer (it auto-detects `GHCUP_INSTALL_BASE_PREFIX` and writes into `/Volumes/MYDRIVE/haskell/.ghcup/`):

```sh
mkdir -p /Volumes/MYDRIVE/haskell
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

After that, `ghcup install ghc 9.6.7` and the rest of the commands in Step 3 install to external. Verify:

```sh
which ghc           # should be under /Volumes/MYDRIVE/haskell/.ghcup/
du -sh /Volumes/MYDRIVE/haskell/.ghcup    # should grow as you install
du -sh ~/.ghcup 2>/dev/null || echo "internal is clean"
```

### Combine the gotcha and the external drive

If you're on macOS with Homebrew LLVM **and** installing to external, both fixes apply. The `.zshrc` block becomes:

```sh
# Haskell toolchain on external drive
export GHCUP_INSTALL_BASE_PREFIX="/Volumes/MYDRIVE/haskell"
export CABAL_DIR="/Volumes/MYDRIVE/haskell/cabal"
# macOS SDK headers (fixes Homebrew LLVM iostream / wchar.h / pthread.h errors)
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null)}"
# Force ghcup to use Apple Clang
alias ghcup='CC=/usr/bin/clang CXX=/usr/bin/clang++ command ghcup'
# ghcup env (source line — must be after the exports above)
[ -f "/Volumes/MYDRIVE/haskell/.ghcup/env" ] && source "/Volumes/MYDRIVE/haskell/.ghcup/env"
```

---

## Step 4 — Editor with HLS

Install the **Haskell** extension in VS Code / Cursor (or the equivalent plugin in your editor of choice). It detects the `haskell-language-server-wrapper` binary that ghcup installed and uses it for inline types, hovers, and errors.

Open any `.hs` file. The bottom bar should say *"Haskell"* with no red squiggles. Hover over an identifier — you should see its type pop up. If you see *"haskell-language-server not found"*, restart the editor (it sometimes caches the toolchain location).

---

## Final verification

In a fresh shell, all of these should succeed:

```sh
ghc --version            # 9.6.x
cabal --version          # 3.10+
ghcup --version          # 0.2.x
which ghc                # ~/.ghcup/bin/ghc or /Volumes/MYDRIVE/haskell/.ghcup/bin/ghc

# Tiny end-to-end test
echo 'main = putStrLn "Hello, Archivist"' > /tmp/hello.hs
runghc /tmp/hello.hs                          # should print Hello, Archivist
ghc -O0 -o /tmp/hello /tmp/hello.hs           # should compile clean
/tmp/hello                                    # should print Hello, Archivist
rm /tmp/hello /tmp/hello.{hi,o} 2>/dev/null
```

All green → return to the lesson's [README.md](README.md) and continue with the GHCi warm-up.
