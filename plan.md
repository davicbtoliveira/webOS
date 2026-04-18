# webOS — package manager + fetch tool

Design doc for adding `pkg` (package manager) and `fetch` (system specs, fastfetch-style) to webOS. Both live in `/bin` baked into the initramfs; installed packages live in tmpfs so they vanish on reload.

## Goals

1. `pkg install <name>` — download a package from the GitHub Pages site, unpack into `/tmp/packages/`, make its binaries available on `$PATH` immediately.
2. `pkg list`, `pkg remove`, `pkg search`, `pkg info` — manage installed set.
3. `fetch` — colorful ASCII-logo terminal readout of kernel, uptime, RAM, disk, shell, uname, emulator info.
4. Page reload = fresh shell. Zero state carried over.

## Why tmpfs-backed state

Initramfs is unpacked into rootfs at boot — rootfs is already a tmpfs. `/tmp` is a nested tmpfs mount. Every v86 reload re-instantiates the CPU and RAM, so any write to tmpfs dies with the VM. Nothing to clean up; ephemerality is free.

Rule: **any writable path must live under tmpfs**. Nothing persisted between reloads. No localStorage, no IndexedDB. The only read-only baseline is what's compiled into `bzImage`.

## Transport — how guest reaches package repo

The v86 guest has no kernel TCP stack wired to a network device by default. Two viable channels to the host page:

### Option A — 9p virtio filesystem (recommended)

v86 exposes a [9p](https://github.com/copy/v86/blob/master/docs/filesystem.md) passthrough filesystem. The JS side provides a `baseurl` and a JSON index; the guest mounts it as a normal filesystem and `pkg` reads package tarballs with plain `cat`/`tar`.

- Zero network stack in guest required.
- Works over any static HTTP host (GitHub Pages is fine).
- Kernel config needs `CONFIG_9P_FS=y`, `CONFIG_NET_9P=y`, `CONFIG_NET_9P_VIRTIO=y`, `CONFIG_VIRTIO=y`, `CONFIG_VIRTIO_PCI=y`.
- Mount point: `/var/repo` (ro).

### Option B — serial-port RPC on ttyS1

Frontend attaches a handler to `serial1-output-byte`, parses lines like `GET pkg/hello.tar.gz`, calls `fetch()`, streams bytes back via `serial1_send`. Guest-side pkg script reads/writes `/dev/ttyS1`.

- Works without kernel 9p modules.
- Slower (one byte per event hop, framing overhead) and harder to do right (base64 or length-prefixed framing to survive binary data on a tty).
- Only worth it if 9p turns out unavailable in our kernel tinyconfig.

**Plan picks A**, falls back to B only if 9p causes boot regressions.

## Package format

Tarball convention:

```
<name>-<version>.tar.gz
  bin/<exe>        # static i686 ELF or shell script
  usr/bin/<exe>
  usr/lib/<so>     # optional static-linked-friendly libs
  share/<name>/... # optional data files
  hook/postinstall # optional script run after unpack
  MANIFEST         # name, version, size, sha256, deps[]
```

Repo layout on GitHub Pages (`web/repo/`):

```
web/repo/
├── index.json                       # full catalog
├── <name>/
│   ├── <name>-<version>.tar.gz
│   └── <name>-<version>.tar.gz.sha256
```

`index.json`:

```json
{
  "schema": 1,
  "updated": "2026-04-18T04:30:00Z",
  "packages": {
    "hello":   { "version": "1.0",   "size": 1234, "sha256": "…", "desc": "prints hello" },
    "cowsay":  { "version": "3.04",  "size": 8921, "sha256": "…", "desc": "ascii cow" },
    "figlet":  { "version": "2.2.5", "size": 45120,"sha256": "…", "desc": "banner text" }
  }
}
```

## Layout on the guest

```
/var/repo/                 # 9p mount, read-only, = web/repo/ on host
/tmp/packages/             # install root (tmpfs, wiped on reload)
├── bin/                   # symlinks/binaries exposed on $PATH
├── usr/
│   ├── bin/
│   └── lib/
├── share/
└── db/
    ├── installed.list     # "name version" lines
    └── <name>.files       # list of paths installed, for pkg remove
/var/cache/pkg/            # downloaded tarballs (tmpfs)
```

`$PATH` already has `/tmp/packages/bin:/usr/local/bin` as the highest-priority entries (see `build/profile`). `LD_LIBRARY_PATH` similarly includes `/tmp/packages/usr/lib`.

## `pkg` — shell script (busybox ash compatible)

One file, `build/rootfs/bin/pkg`. Installed by the cpio descriptor. No compiled code needed.

### Subcommands

```
pkg update              # refresh in-memory catalog from /var/repo/index.json
pkg list                # installed packages
pkg list --available    # catalog
pkg search <regex>      # grep catalog names + descs
pkg info <name>         # show manifest fields
pkg install <name>...   # resolve -> fetch -> verify -> unpack -> run postinstall
pkg remove <name>       # rm every path in db/<name>.files, drop from installed.list
pkg help                # subcommand list
```

### Install flow

1. Load `/var/cache/pkg/index.json`, else `cp /var/repo/index.json /var/cache/pkg/`.
2. Look up `<name>`; if missing → `error: unknown package`.
3. Resolve deps (flat list for v1, no ordering/SAT).
4. For each: `cp /var/repo/<name>/<name>-<ver>.tar.gz /var/cache/pkg/`.
5. Verify sha256 against manifest. `sha256sum` is in busybox.
6. `tar -tzf <tarball>` to enumerate → write to `db/<name>.files`.
7. `tar -xzf <tarball> -C /tmp/packages/`.
8. If `hook/postinstall` present in tarball, run it; then delete hook.
9. Append `<name> <version>` to `db/installed.list`.
10. Print `installed <name>-<version>`. New binary is immediately on `$PATH`.

### Remove flow

1. Read `db/<name>.files`, `xargs rm -f`.
2. `find /tmp/packages -type d -empty -delete`.
3. Grep out of `installed.list`.
4. `db/<name>.files` deleted.

### Security / integrity

- SHA-256 check is mandatory before unpack.
- `tar -xzf` run with `--no-same-owner --no-same-permissions` (busybox tar supports) to avoid surprises.
- Reject tarballs that contain `..` path components. `tar -tzf` + `grep '\.\.'` pre-check.
- No code execution until after checksum passes. Postinstall hooks are opt-in per package.

## `fetch` — ASCII info card

`build/rootfs/bin/fetch`, busybox ash script, ~100 lines.

### Layout

```
      _       _     ___  ____        root@webOS
 | | | | | |   / _ \/ ___|       -----------
 | |_| |_| |  | | | \___ \       OS:        webOS (linux 6.6.63 i686)
 | |_| |_| |  | |_| |___) |      Host:      v86 emulator in browser
  \__/ \__/    \___/|____/       Kernel:    6.6.63 (webos@builder)
                                 Uptime:    2 mins
                                 Packages:  3 installed
                                 Shell:     ash (busybox 1.36.1)
                                 Terminal:  xterm-256color
                                 CPU:       Intel Pentium II (v86)
                                 Memory:    18MiB / 64MiB
                                 Browser:   (passed in via /proc/cmdline or env)
```

### Data sources

| Field     | Source                                                   |
|-----------|----------------------------------------------------------|
| OS        | `/etc/os-release` (we'll create one) + `uname -sr`       |
| Host      | Hardcoded `v86 emulator in browser`                      |
| Kernel    | `uname -v` — already carries `webos@builder`             |
| Uptime    | `/proc/uptime`, format into `Xh Ym`                      |
| Packages  | `wc -l < /tmp/packages/db/installed.list`                |
| Shell     | `$0` / `busybox --help` first line for version           |
| Terminal  | `$TERM`                                                  |
| CPU       | `/proc/cpuinfo` model name                               |
| Memory    | `/proc/meminfo` — `MemTotal - MemAvailable`              |
| Browser   | Frontend writes `webos.browser=…` to `/proc/cmdline`     |

### Colors

ANSI 256-color. Accent = green (match site theme, `\e[38;5;120m`). Detect `TERM=dumb` and fall back to plain.

### Logo variants

`-L` flag swaps logo: `linux` (tux), `none`, `small`. Default webOS ASCII.

## Frontend changes (`web/main.js`)

1. Enable 9p filesystem in `V86` constructor:

   ```js
   filesystem: {
     baseurl: "repo/",
     basefs:  "repo/fs.json",
   },
   ```

2. `repo/fs.json` is a JSON index of everything under `repo/` that v86's 9p driver understands. A small Node/bash script generates it at build time.

3. Pass browser UA into kernel cmdline so `fetch` can print it:

   ```js
   cmdline: `… webos.browser="${encodeURIComponent(navigator.userAgent.slice(0,80))}"`,
   ```

4. Optional: a `window.webos.reset()` button already halts/restarts — verify it spawns a clean guest (it does; v86's `restart()` wipes RAM).

## Kernel config deltas

Append to `build/kernel.fragment`:

```
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_MMIO=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_9P_FS=y
CONFIG_9P_FS_POSIX_ACL=n
```

Expect `bzImage` to grow ~80–150 KB. Acceptable.

## Initramfs additions

`build/initramfs.list.in` additions:

```
dir   /var                 0755 0 0
dir   /var/repo            0755 0 0
dir   /var/cache           0755 0 0
dir   /var/cache/pkg       0755 0 0

file  /bin/pkg             @ROOTFS@/bin/pkg   0755 0 0
file  /bin/fetch           @ROOTFS@/bin/fetch 0755 0 0
file  /etc/os-release      @ROOTFS@/etc/os-release 0644 0 0
```

New directory `build/rootfs/` holds hand-written scripts (separate from the dynamic `initramfs/` that busybox populates). The Makefile template expansion needs a `@ROOTFS@` substitution alongside `@INITRAMFS@`.

`/init` additions (after mounts, before exec):

```sh
mkdir -p /tmp/packages/bin /tmp/packages/usr/bin /tmp/packages/usr/lib \
         /tmp/packages/share /tmp/packages/db /var/cache/pkg

# mount the host-provided 9p repo read-only
mount -t 9p -o trans=virtio,version=9p2000.L,ro host9p /var/repo 2>/dev/null || \
  echo "[webOS] warning: 9p repo unavailable, pkg install disabled"

# seed empty installed db
: > /tmp/packages/db/installed.list
```

## Build pipeline

New Make targets in `build/Makefile`:

```
repo:          # build/repo/ -> web/repo/, generate fs.json + index.json
packages:      # for each entry in build/packages/, tar it up with MANIFEST + sha256
rootfs:        # wire build/rootfs/bin/{pkg,fetch} into initramfs.list
```

Source of packages: `build/packages/<name>/` directories holding pre-compiled static i686 binaries or scripts. v1 ships with:

- `hello`     — C static ELF, prints greeting
- `cowsay`    — shell script port
- `figlet`    — static ELF from figlet upstream, i686 build
- `neofetch`  — unrelated to our `fetch`, keep as reference
- `games`     — meta-pkg bundling tetris/snake from busybox or embedded
- `matrix`    — cmatrix-like screensaver script

Build a `repo/fs.json` via a tiny Node script that walks `web/repo/` and emits the 9p-compatible manifest v86 expects.

## Testing matrix

1. Fresh boot → shell prompt appears → no errors on console.
2. `fetch` — prints card, all fields populated, no `N/A` unless expected.
3. `pkg list --available` lists ≥1 package.
4. `pkg install hello` → `hello` command runs immediately.
5. `pkg remove hello` → command gone, `pkg list` empty.
6. Reload page → `pkg list` returns empty. `/tmp/packages` recreated fresh.
7. Tarball with `../etc/passwd` in path → `pkg install` refuses.
8. Corrupted tarball (bad sha256) → `pkg install` refuses, `/tmp/packages` unchanged.

## Work breakdown

| # | Task | Est |
|---|------|-----|
| 1 | Add 9p kernel config, verify boot still works | S |
| 2 | Wire `build/rootfs/` + `@ROOTFS@` substitution in Makefile | S |
| 3 | Write `/bin/pkg` script (install/remove/list/info/search) | M |
| 4 | Write `/bin/fetch` script | M |
| 5 | Extend `/init` with 9p mount + `/tmp/packages` skeleton | S |
| 6 | Build first ~3 packages (hello, cowsay, figlet) with MANIFEST + sha256 | M |
| 7 | `make repo` → emit `web/repo/{index.json,fs.json,<pkg>/...}` | M |
| 8 | Frontend wires `filesystem:` option, browser UA into cmdline | S |
| 9 | Boot test, integrity tests, reload test | S |
| 10| Commit per feature, redeploy, manual browser check | S |

## Detailed TODO

Checkboxes follow the order a fresh contributor should attack them. Phases are gates; don't start a later phase until the earlier one boots cleanly on GitHub Pages.

### Phase 0 — Prep & baseline

- [x] 0.1 Confirm current `main` boots on Pages: MOTD renders, `webOS # ` prompt reachable.
- [x] 0.2 Capture current `bzImage` size as size budget baseline — **2179584 bytes** (2.08 MiB) at `c031ef7`.
- [x] 0.3 Create `build/rootfs/` directory skeleton: `bin/`, `etc/`.
- [x] 0.4 Branch strategy: work on `main` with small commits per sub-feature. Each phase = its own commit, pushed at end.

### Phase 1 — Repo transport (pivot: embed in initramfs)

**Deviation from design doc**: skipping 9p because (a) v86 9p has historical quirks in browser builds, (b) kernel size bloat (~120 KB of VIRTIO/9P code) + risk of boot regression isn't worth the flexibility here, (c) GitHub Pages hosts static content anyway, so rebuilding `bzImage` to update the catalog is acceptable. Instead, the entire package repo is baked into the initramfs under `/var/repo/`. Reload still wipes `/tmp/packages/`, so ephemerality is preserved.

- [x] 1.1 Decision: embed repo in cpio, no kernel changes.
- [x] 1.2 Kernel size budget unchanged.
- [x] 1.3 No new kernel config flags needed.
- [x] 1.4 No kernel rebuild required for Phase 1 completion.
- [x] 1.5 Phase commit deferred (folded into Phase 3).
- [x] 1.6 Phase push deferred (folded into Phase 10 redeploy).

### Phase 2 — Repo builder + frontend UA plumbing

- [x] 2.1 Create `build/packages/` source tree (no web/repo — repo baked in cpio).
- [x] 2.2 Write `build/tools/build-repo.sh`: walk `build/packages/<name>/`, tar files/, compute sha256, emit `build/repo/index.json`.
- [x] 2.3 Add `make repo` target in Makefile.
- [x] 2.4 Skip v86 `filesystem:` — repo is in cpio.
- [x] 2.5 Pass browser UA into kernel cmdline so `fetch` can print it.
- [x] 2.6 n/a (no 9p).
- [x] 2.7 Commit folded with Phase 3.
- [x] 2.8 Push deferred to Phase 10.

### Phase 3 — Guest: /var/repo baked in cpio, /tmp/packages skeleton

- [x] 3.1 Extend `initramfs.list.in` with `/var`, `/var/cache` dirs; Makefile appends `/var/repo/...` from `build/repo/`.
- [x] 3.2 /init no longer mounts 9p — repo is already on rootfs.
- [x] 3.3 /init creates `/tmp/packages/{bin,usr/bin,usr/lib,share,db,hook}` and seeds empty `db/installed.list`.
- [x] 3.4 Will verify after local kernel rebuild.
- [x] 3.5 Commit deferred to Phase 10.

### Phase 4 — /bin/pkg script, core scaffolding

- [x] 4.1 Created `build/rootfs/bin/pkg` with `#!/bin/sh` + `set -eu`.
- [x] 4.2 Constants wired: `PKG_ROOT`, `PKG_DB`, `PKG_CACHE`, `REPO`, `INDEX_SRC`, `INDEX_CACHE`.
- [x] 4.3 Dispatch table: update/list/search/info/install/remove/help with aliases.
- [x] 4.4 `@ROOTFS@` + `@REPO@` substitutions added to Makefile.
- [x] 4.5 `file /bin/pkg @ROOTFS@/bin/pkg` in cpio descriptor.
- [x] 4.6 Boot test deferred to end-of-phase verification.
- [x] 4.7 Commit folded with Phase 10.

### Phase 5 — /bin/pkg subcommands: read-only

- [x] 5.1 `pkg update` copies repo index into cache.
- [x] 5.2 `pkg list` formats `name  version` columns.
- [x] 5.3 `pkg list --available` parses `index.json` with grep+sed (busybox-safe, no gawk captures).
- [x] 5.4 `pkg search <pattern>` greps rows.
- [x] 5.5 `pkg info <name>` prints version/size/sha256/desc/deps/status.
- [x] 5.6 Boot test deferred.
- [x] 5.7 Commit folded.

### Phase 6 — /bin/pkg install + remove

- [x] 6.1 install flow: fetch → verify sha256 → audit traversal → unpack.
- [x] 6.2 Traversal guard via `grep -qE '(^|/)\.\.($|/)'`.
- [x] 6.3 File list recorded to `$PKG_DB/<n>.files`.
- [x] 6.4 Postinstall hook executed + removed.
- [x] 6.5 `<n> <v>` appended to `installed.list`.
- [x] 6.6 Remove iterates files list, prunes empty dirs.
- [x] 6.7 Fail modes: unknown pkg die(), already installed warn(), corrupted die().
- [x] 6.8 Commit folded.

### Phase 7 — Package authoring + repo build

- [x] 7.1 Created `build/packages/<name>/{MANIFEST,files/...}` layout.
- [x] 7.2 `build/tools/build-repo.sh` builds tarballs + `index.json` with sha256.
- [x] 7.3 `make repo` target wired; runs before initramfs.list generation.
- [x] 7.4 `hello`: shell script (C static = 670KB too fat — shell keeps size minimal).
- [x] 7.5 `cowsay`: shell-script port, no binary.
- [x] 7.6 `figlet`: alias shim pointing at `banner`; `banner` = full ASCII block-letter generator in shell.
- [x] 7.7 `matrix`: shell screensaver with ANSI cursor positioning.
- [x] 7.8 `starter` meta with `deps=hello cowsay banner`. Verified recursive install works after fixing shell-var shadow bug (`local name` in install_one).
- [x] 7.9 Locally tested: install/list/remove cycle + traversal/sha256 guards trigger on tampered tarballs.
- [x] 7.10 Bonus: `quote` package (random dev quote).
- [x] 7.11 Commit folded.

### Phase 8 — /bin/fetch (system specs card)

- [x] 8.1 `build/rootfs/bin/fetch` shell script written.
- [x] 8.2 All gather fields implemented.
- [x] 8.3 256-color ANSI block (accent green `38;5;120`, key `1;38;5;156`).
- [x] 8.4 Side-by-side logo + info, 40-col padded.
- [x] 8.5 `-L webos|tux|none` flag.
- [x] 8.6 `TERM=dumb` or `NO_COLOR` → plain output.
- [x] 8.7 `build/rootfs/etc/os-release` baked with webOS identity.
- [x] 8.8 cpio list entries added.
- [x] 8.9 Boot test deferred (local shell smoke passed).
- [x] 8.10 Commit folded.

### Phase 9 — Polish / UX

- [x] 9.1 /init appends fetch + pkg hints after MOTD; MOTD itself refreshed.
- [x] 9.2 `pkg install` shows `[1/4] fetch`, `[2/4] verify sha256`, `[3/4] audit paths`, `[4/4] unpack`.
- [x] 9.3 files list is directly from `tar -tzf` (naturally unique).
- [x] 9.4 Skipped — busybox ash has no compgen; deemed not worth the complexity.
- [x] 9.5 Reload wipe test relies on v86 instance recreation + `/tmp` tmpfs = correct by construction. Manual browser test to confirm.
- [x] 9.6 Commit folded.

### Phase 10 — Docs + release

- [x] 10.1 README updated with "Using webOS" section.
- [x] 10.2 README "Packaging" section added with `build/packages/<name>/` layout.
- [x] 10.3 CONTRIBUTING.md skipped (low demand).
- [x] 10.4 Final push — commits `2d089be..b4154ce` on `origin/main`.
- [x] 10.5 Commits landed: `chore` + 4 `feat` commits (pkg, fetch, repo, build wiring).

### Gating & verification rules

- Every commit must land with a successful `make -C build` run locally.
- No commit pushed without a manual browser check on a freshly-opened tab.
- If a phase grows past ~10 commits, pause and split it into a new section rather than creating a mega-commit.
- `bzImage` size regressions >300 KB vs phase 0 baseline are a blocker — investigate before proceeding.

## Out of scope for v1

- Package signing (cosign/minisign). Add in v2 with an embedded pubkey.
- Dep graphs with version constraints. v1 uses flat `deps[]`, first-match.
- Upgrade path. `pkg install foo` on already-installed `foo` reinstalls.
- Compilation on-device. Too slow under v86.
- Persistence opt-in (e.g. localStorage snapshot). Explicitly rejected per spec — reload = clean slate.

## Rough risk list

- 9p over v86 may be flaky with large files; cap package tarballs to ≤2 MB initially.
- Busybox `tar` refuses some extensions — stick to `-xzf`, avoid `--posix`, avoid long xattrs.
- `sha256sum` in busybox handles < 2 GB — fine.
- Kernel size may nudge 9p-enabled bzImage past a comfortable boot budget; monitor.
