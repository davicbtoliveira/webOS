# webOS

Minimal Linux distro built from scratch, running in the browser via [v86](https://github.com/copy/v86).

- Kernel: vanilla `linux-6.6.63` built from source (x86_32).
- Userspace: static `busybox-1.36.1`, single binary with applet symlinks.
- Emulator: `v86` WebAssembly x86 emulator.
- Frontend: plain HTML/CSS/JS. No build step. No bundler. No framework.

## Layout

```
webOS/
├── build/
│   ├── Makefile               # orchestrator
│   ├── kernel.fragment        # kernel .config deltas
│   ├── busybox.fragment       # busybox .config deltas
│   ├── initramfs.list.in      # gen_init_cpio descriptor template
│   ├── init.sh                # /init (stage 1 mounts + exec /sbin/init)
│   ├── inittab, profile, motd
│   ├── packages/              # package source tree (MANIFEST + files/)
│   ├── rootfs/                # hand-written guest scripts (/bin/pkg, /bin/fetch)
│   ├── repo/                  # generated: catalog + tarballs (baked into initramfs)
│   └── tools/                 # build-repo.sh
├── src/                       # kernel + busybox sources (fetched)
├── dist/                      # dist outputs (bzImage)
├── web/                       # static site
│   ├── index.html
│   ├── style.css
│   ├── main.js
│   ├── vendor/                # libv86.js, xterm.js (fetched)
│   └── images/                # bzImage, seabios.bin, vgabios.bin (published)
└── README.md
```

## Build deps

Arch:
```
sudo pacman -S base-devel bc lib32-glibc qemu-base qemu-system-x86 python
```

Needed binaries on `$PATH`: `gcc`, `make`, `bison`, `flex`, `bc`, `curl`, `xz`, `python3`.
For QEMU smoke test: `qemu-system-i386`.

## Build

From repo root:

```
make -C build fetch     # download kernel + busybox tarballs
make -C build busybox   # build static busybox into build/initramfs/
make -C build kernel    # build bzImage with embedded initramfs
make -C build web       # fetch libv86, xterm, BIOSes
make -C build           # everything
```

Outputs:
- `dist/bzImage`, `web/images/bzImage`
- `web/images/seabios.bin`, `web/images/vgabios.bin`
- `web/vendor/libv86.js`, `web/vendor/v86.wasm`
- `web/vendor/xterm.js`, `web/vendor/xterm.css`

## Run

QEMU smoke test:
```
make -C build run
```

Serve the web UI:
```
make -C build serve
# open http://localhost:8000/
```

v86 requires a real HTTP origin — opening `index.html` as `file://` will break WASM fetch.

## Kernel config

`build/kernel.fragment` — appended on top of `tinyconfig`. Key flags: `X86_32`, `SERIAL_8250_CONSOLE`, `DEVTMPFS_MOUNT`, `INITRAMFS_SOURCE` pointed at `build/initramfs/`. No VGA/framebuffer — serial only.

## Boot flow

1. v86 loads `seabios.bin`, jumps to `bzImage` with `cmdline=console=ttyS0 …`.
2. Kernel unpacks initramfs into rootfs (device nodes + `/bin/busybox` + `/bin/pkg` + `/bin/fetch` + `/var/repo/`).
3. Kernel execs `/init`.
4. `/init` mounts `/proc`, `/sys`, `/dev`, `/tmp`, `/run`; creates `/tmp/packages/…` skeleton; prints MOTD; `exec /sbin/init`.
5. `/sbin/init` reads `/etc/inittab`, respawns `/bin/sh` on ttyS0.
6. Serial I/O bridged to xterm.js via `serial0-output-byte` / `serial0_send`.

## Using webOS

Once the shell prompts:

```
fetch                      # ASCII info card (os/kernel/uptime/cpu/ram/browser)
fetch -L tux               # swap logo
pkg help                   # package commands
pkg list --available       # catalog
pkg install hello          # unpacks into /tmp/packages/ (on PATH)
hello you                  # run it
pkg install starter        # installs hello + cowsay + banner together
pkg remove cowsay
pkg info banner
```

Everything installed under `/tmp/packages/` lives in tmpfs and is **wiped on browser reload** — every session starts clean. That's by design.

## Packaging

To add a package, create `build/packages/<name>/`:

```
build/packages/<name>/
├── MANIFEST              # version=, desc=, deps=
└── files/                # tree to tar and extract into /tmp/packages/
    ├── bin/<exe>
    └── share/<name>/…
```

Rebuild the kernel (repo is baked into initramfs):

```
make -C build repo        # rebuild build/repo/ (index + tarballs + sha256)
make -C build kernel      # embed in bzImage
```

## Licenses

- Linux kernel: GPL-2.0
- BusyBox: GPL-2.0
- v86: BSD-2-Clause
- xterm.js: MIT
