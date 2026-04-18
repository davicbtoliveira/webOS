# webOS Codebase Research Report

## Project Overview

**webOS** is a minimal Linux distribution built from scratch that runs entirely in a web browser via the [v86](https://github.com/copy/v86) WebAssembly x86 emulator. It's an educational/experimental project that demonstrates running a full Linux system (kernel + userspace) client-side in a web browser.

## Technology Stack

### Languages
- **C** (Linux kernel, BusyBox)
- **Shell scripting** (init scripts)
- **JavaScript** (web frontend)
- **HTML/CSS** (web UI)

### Frameworks/Tools
- **v86** - WebAssembly x86 emulator
- **xterm.js** - Terminal emulator for web
- **BusyBox** - Single-binary userspace utilities (version 1.36.1)
- **Linux kernel** (version 6.6.63, 32-bit x86)

### Build Tools
- **Make** - Primary build system
- **GCC** - C compiler (with i686 cross-compilation)
- **Python 3** - For serving the web UI

## Directory Structure

```
webOS/
├── build/          # Build system: Makefile, configs, init scripts
├── src/            # Source code (kernel + busybox tarballs - fetched)
├── dist/           # Build output: bzImage kernel
├── web/            # Static web frontend
│   ├── index.html  # Main HTML page
│   ├── main.js     # JavaScript orchestration
│   ├── style.css   # Styling
│   ├── vendor/     # Third-party JS (libv86, xterm.js)
│   └── images/     # BIOS binaries, kernel image
├── .github/        # CI/CD workflows
└── README.md      # Project documentation
```

## Architecture

### Boot Flow

1. Browser loads `index.html` which initializes v86 emulator
2. v86 loads SeaBIOS, then boots Linux kernel (bzImage) with serial console
3. Kernel unpacks initramfs (containing BusyBox)
4. Kernel executes `/init` script which:
   - Mounts pseudo-filesystems (/proc, /sys, /dev, /tmp)
   - Installs BusyBox applet symlinks
   - Sets hostname
   - Prints MOTD
   - Executes `/sbin/init` (which runs getty on ttyS0)
5. Serial output is piped to xterm.js via `emulator.serial0_output_byte`
6. Keyboard input from xterm.js is sent to emulator via `emulator.serial0_send`

### Key Configuration

| Component | Configuration |
|-----------|----------------|
| **Kernel** | x86_32 (i386), compiled with tinyconfig + custom fragment |
| **Console** | Serial only (ttyS0) - no VGA/framebuffer |
| **Userspace** | Static BusyBox with ash shell, vi editor, init system |
| **Emulator** | 64MB RAM, 2MB VGA memory |

## Entry Points

### Build Entry Point
- `make -C build` - Main build command that orchestrates all targets

### Runtime Entry Points
- `make -C build serve` - Starts HTTP server for web UI
- `make -C build run` - QEMU smoke test (runs kernel in QEMU)
- Web browser accesses `http://localhost:8000/`

### Boot Entry Point
- Kernel: `/init` script in initramfs
- Init system: `getty` on ttyS0 -> `/bin/sh`

## Key Configuration Files

| File | Purpose |
|------|---------|
| `build/Makefile` | Main build orchestration |
| `build/kernel.fragment` | Linux kernel config (appended to tinyconfig) |
| `build/busybox.fragment` | BusyBox configuration |
| `build/init.sh` | Init script (stage 1) |
| `build/inittab` | Init system configuration |
| `build/motd` | Message of the day |
| `web/main.js` | Browser-side emulator orchestration |

## Dependencies

### Fetched During Build
- Linux kernel 6.6.63 (from kernel.org)
- BusyBox 1.36.1 (from busybox.net)
- v86 (libv86.js, v86.wasm, seabios.bin, vgabios.bin - from copy.sh/v86)
- xterm.js 5.3.0 (from jsdelivr CDN)

### Build-time Dependencies
- gcc, make, bison, flex, bc, curl, xz, python3
- i686-linux-gnu cross-compiler toolchain

## Build System

The build is entirely Makefile-based with no fancy build tools:

### Build Targets
- `make -C build fetch` - Download source tarballs
- `make -C build busybox` - Build static BusyBox
- `make -C build kernel` - Build Linux kernel with initramfs
- `make -C build web` - Fetch v86 + xterm.js assets
- `make -C build` - Build everything

### Output Artifacts
- `dist/bzImage` / `web/images/bzImage` - Linux kernel image
- `web/images/seabios.bin`, `vgabios.bin` - BIOS binaries
- `web/vendor/libv86.js`, `v86.wasm` - Emulator
- `web/vendor/xterm.js`, `xterm.css` - Terminal UI

## Special Features & Specificities

### Unique Aspects

1. **No build step for frontend** - Plain HTML/CSS/JS, no bundler
2. **Serial console only** - No graphics, text-only via serial
3. **Static BusyBox** - Single binary with applet symlinks (no shared libs)
4. **32-bit kernel** - Compiled for i386 (x86_32), runs on emulated CPU
5. **Shim for cross-compilation** - Uses i686-linux-gnu-* toolchain
6. **GitHub Pages deployment** - CI/CD automatically builds and deploys to GitHub Pages
7. **Minimal footprint** - Tinyconfig + embedded kernel, minimal initramfs

### Performance
- **Boot time:** Approximately 100-200ms (measured in browser)

### Licenses
- Linux kernel: GPL-2.0
- BusyBox: GPL-2.0
- v86: BSD-2-Clause
- xterm.js: MIT

## How It Works - Detailed Flow

### 1. Web Browser Side
The user visits the web page which loads:
1. xterm.js terminal emulator
2. v86 WebAssembly emulator
3. BIOS binaries (SeaBIOS, VGA BIOS)
4. Linux kernel image (bzImage)

### 2. Emulation Initialization
v86 initializes with:
- 64MB RAM
- 2MB VGA memory
- SeaBIOS as boot firmware
- Kernel image loaded at memory location 0x100000

### 3. Boot Process
1. SeaBIOS runs, finds and executes bootable disk (kernel)
2. Linux kernel starts with serial console (ttyS0) as primary console
3. Kernel decompresses and mounts initramfs
4. Kernel executes `/init` from initramfs

### 4. Userspace Initialization
The init script (`build/init.sh`):
1. Mounts pseudo-filesystems (/proc, /sys, /dev, /tmp)
2. Creates device nodes (console, tty, null, zero, random)
3. Installs BusyBox applet symlinks (ls, cat, rm, etc.)
4. Sets hostname to "webOS"
5. Reads `/etc/inittab` for runlevel configuration
6. Prints MOTD (Message of the Day)
7. Starts getty on serial console (ttyS0)

### 5. Interactive Session
- User types in xterm.js
- Characters sent via `serial0_send()` to emulator
- Kernel receives input on ttyS0
- Shell (ash) processes commands
- Output sent back via `serial0_output_byte` to xterm.js

## Summary

webOS is an elegant, educational project that demonstrates how Linux systems work at a fundamental level, from boot to shell, all running in a web browser. It showcases:
- Linux kernel compilation and configuration
- BusyBox as a minimal userspace
- initramfs concepts
- init system behavior
- Serial console communication
- WebAssembly emulation technology

The entire system runs client-side in the browser with no server-side computation required once the assets are loaded.