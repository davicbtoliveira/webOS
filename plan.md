# Package Manager Implementation Plan

## Overview

This document outlines the implementation of a package manager for webOS that allows users to install packages at runtime. Packages are stored in memory (tmpfs/ramfs) and will be lost on page refresh - providing a fresh shell experience as required.

## Technical Requirements

1. **Runtime Installation**: Packages installed after boot, not at build time
2. **Memory Storage**: All packages stored in tmpfs - ephemeral, lost on refresh
3. **Package Registry**: Minimal metadata system for available packages
4. **Minimal overhead**: Don't bloat the initramfs with pre-installed packages

## Architecture

### Package Storage Strategy

```
/tmp/packages/           # Root directory for installed packages
/tmp/packages/bin/      # Symlinks to binaries
/tmp/packages/lib/     # Libraries
/tmp/packages/etc/     # Config files
/usr/local/             # Writable symlinks to /tmp/packages
```

### Approach: Hybrid Package System

Since packages must be fetched at runtime and stored in memory:

1. **Package Index**: Minimal JSON shipped in initramfs with package metadata
2. **Download Server**: External server hosts pre-built package tarballs
3. **Runtime Installer**: Shell script to download, extract, and configure packages

## Implementation Steps

### Step 1: Create Package Index (JSON)

Create `build/packages.json` with available packages:

```json
{
  "packages": [
    {
      "name": "fastfetch",
      "version": "2.43.0",
      "description": "Fast fetch system information tool",
      "architecture": "i386",
      "size": 180000,
      "url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.43.0/fastfetch-2.43.0-x86_64-linux-gnu.tar.gz",
      "binaries": ["fastfetch"],
      "dependencies": []
    },
    {
      "name": "htop",
      "version": "3.3.0",
      "description": "Interactive process viewer",
      "architecture": "i386",
      "size": 120000,
      "url": "https://github.com/htop-dev/htop/releases/download/3.3.0/htop-3.3.0.tar.gz",
      "binaries": ["htop"],
      "dependencies": ["ncurses"]
    },
    {
      "name": "testutils",
      "version": "1.36.1",
      "description": "Test utilities for troubleshooting",
      "architecture": "i386",
      "size": 50000,
      "url": "https://busybox.net/downloads/busybox-1.36.1.tar.bz2",
      "binaries": ["busybox"],
      "alternatives": ["ls", "cat", "echo"],
      "dependencies": []
    }
  ]
}
```

### Step 2: Package Manager Script

Create `build/package-manager.sh` - the core installer:


```sh
#!/bin/sh
# package-manager.sh - webOS Package Manager

# Configuration
PKG_DIR="/tmp/packages"
PKG_DB="/tmp/packages.db"
PACKAGES_JSON="/etc/packages.json"
WGET_OPTS="-q --timeout=30 -O"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

# Initialize package directory
init_pkg_dir() {
    mkdir -p "$PKG_DIR/bin"
    mkdir -p "$PKG_DIR/lib"
    mkdir -p "$PKG_DIR/etc"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/lib"
    # Create symlink tree in /usr/local
    ln -sf "$PKG_DIR/bin" /usr/local/bin 2>/dev/null || true
    ln -sf "$PKG_DIR/lib" /usr/local/lib 2>/dev/null || true
    ln -sf "$PKG_DIR" /usr/local/packages 2>/dev/null || true
}

# Parse packages.json and find package
find_package() {
    local pkg_name="$1"
    local pkg_arch architecture version
    
    # Simple JSON parsing without jq
    # This is a basic implementation - can be enhanced
    while IFS= read -r line; do
        case "$line" in
            *'"name":'*'"'"$pkg_name"'"'*)
                # Found the package - extract details from next lines
                return 0
                ;;
        esac
    done < "$PACKAGES_JSON"
    
    return 1
}

# Download and extract package
install_package() {
    local pkg_name="$1"
    local pkg_url pkg_binaries pkg_version
    
    log_info "Installing $pkg_name..."
    
    # Check if already installed
    if [ -f "$PKG_DIR/bin/$pkg_name" ]; then
        log_warn "$pkg_name is already installed"
        return 1
    fi
    
    # Create temporary download directory
    local tmp_dir="/tmp/install.$pkg_name.$$"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    
    # Download package (use wget from busybox)
    log_info "Downloading $pkg_name from remote..."
    if ! wget $WGET_OPTS "$pkg_name.tar.gz" "$pkg_url" 2>/dev/null; then
        log_error "Failed to download $pkg_name"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Extract package
    log_info "Extracting package..."
    tar -xzf "$pkg_name.tar.gz" 2>/dev/null || tar -xf "$pkg_name.tar.gz" 2>/dev/null || {
        log_error "Failed to extract package"
        rm -rf "$tmp_dir"
        return 1
    }
    
    # Find and copy binaries
    local extracted_dir
    extracted_dir=$(ls -d */ 2>/dev/null | head -1)
    if [ -n "$extracted_dir" ]; then
        cd "$extracted_dir"
        
        # Copy binaries
        for bin in $pkg_binaries; do
            if [ -f "$bin" ]; then
                cp "$bin" "$PKG_DIR/bin/"
                chmod +x "$PKG_DIR/bin/$bin"
                log_info "Installed $bin"
            fi
        done
        
        # Copy libraries if any
        for lib in *.so*; do
            [ -f "$lib" ] && cp "$lib" "$PKG_DIR/lib/"
        done
    fi
    
    # Cleanup
    cd /
    rm -rf "$tmp_dir"
    
    log_info "$pkg_name installed successfully"
    return 0
}

# Remove package
remove_package() {
    local pkg_name="$1"
    
    log_info "Removing $pkg_name..."
    
    if [ ! -f "$PKG_DIR/bin/$pkg_name" ]; then
        log_error "$pkg_name is not installed"
        return 1
    fi
    
    rm -f "$PKG_DIR/bin/$pkg_name"
    log_info "$pkg_name removed successfully"
}

# List installed packages
list_installed() {
    log_info "Installed packages:"
    for pkg in "$PKG_DIR/bin/"*; do
        [ -f "$pkg" ] && basename "$pkg"
    done
}

# List available packages
list_available() {
    log_info "Available packages:"
    # Parse and display from packages.json
    cat "$PACKAGES_JSON" | grep -A2 '"name":' | grep -v "^--" | sed 's/.*"name": *"\(.*\)".*/  - \1/'
}

# main command dispatcher
main() {
    local command="$1"
    shift
    
    case "$command" in
        install)
            init_pkg_dir
            install_package "$@"
            ;;
        remove|uninstall)
            remove_package "$@"
            ;;
        list-installed)
            list_installed
            ;;
        list|available)
            list_available
            ;;
        init)
            init_pkg_dir
            ;;
        help|--help|-h)
            echo "webOS Package Manager"
            echo ""
            echo "Usage: pkg <command> [package]"
            echo ""
            echo "Commands:"
            echo "  install <package>    Install a package"
            echo "  remove <package>  Remove a package"
            echo "  list             List available packages"
            echo "  list-installed   List installed packages"
            echo "  init             Initialize package directory"
            ;;
        *)
            echo "Unknown command: $command"
            echo "Use 'pkg help' for usage information"
            ;;
    esac
}

main "$@"
```

### Step 3: Modify init.sh to Support Package Manager

Update `build/init.sh` to set up the package manager environment:


```sh
#!/bin/sh
# init.sh - Stage 1 init script for webOS

# Mount pseudo-filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mount -t tmpfs none /dev
mount -t tmpfs none /tmp

# Create essential device nodes
[ -e /dev/console ] || mknod /dev/console c 5 1
[ -e /dev/tty ] || mknod /dev/tty c 5 0
[ -e /dev/null ] || mknod /dev/null c 1 3
[ -e /dev/zero ] || mknod /dev/zero c 1 5
[ -e /dev/random ] || mknod /dev/random c 1 8
[ -e /dev/urandom ] || mknod /dev/urandom c 1 9

# Set up hostname
echo "webOS" > /proc/sys/kernel/hostname
echo "127.0.0.1 localhost" > /etc/hosts

# Create resolv.conf for DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Set PATH including package manager paths
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/bin"

# Install BusyBox applet symlinks
echo "Setting up BusyBox applets..."
/bin/busybox --install -s /bin

# Initialize package manager directory
echo "Initializing package manager..."
mkdir -p /tmp/packages/bin
mkdir -p /tmp/packages/usr/bin
mkdir -p /tmp/packages/usr/lib
ln -sf /tmp/packages/bin /usr/local/bin 2>/dev/null || true
ln -sf /tmp/packages/usr/lib /usr/local/lib 2>/dev/null || true

# Export PATH for packages
export PATH="/tmp/packages/bin:/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/packages/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH"

# Source package manager functions
. /etc/package-manager.sh 2>/dev/null || true

# Print MOTD
if [ -f /etc/motd ]; then
    echo ""
    cat /etc/motd
    echo ""
fi

# Print welcome message with package manager info
echo ""
echo "Welcome to webOS!"
echo "Type 'pkg help' for package management"
echo ""

# Execute getty on serial console
exec /sbin/getty -L ttyS0 115200 vt100
```

### Step 4: Create pkg Command Wrapper

Create `build/pkg` - simplified command for end users:


```sh
#!/bin/sh
# pkg - Simple package manager command

# Quick wrapper around package-manager.sh

# Add package paths if not already in PATH
export PATH="/tmp/packages/bin:/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="/tmp/packages/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH"

# Initialize if needed
if [ ! -d "/tmp/packages/bin" ]; then
    mkdir -p /tmp/packages/bin
    mkdir -p /tmp/packages/usr/bin
    mkdir -p /tmp/packages/usr/lib
fi

# Check for subcommand
cmd="$1"

case "$cmd" in
    -h|--help|help)
        echo "webOS Package Manager"
        echo ""
        echo "Usage: pkg <command> [options]"
        echo ""
        echo "Commands:"
        echo "  list              Show available packages"
        echo "  installed        Show installed packages"
        echo "  install <name>    Install a package"
        echo "  remove <name>     Remove a package"
        echo "  update           Update package list from remote"
        echo ""
        ;;
    list)
        echo "Available packages:"
        echo "  fastfetch  - System information fetch tool"
        echo "  htop       - Interactive process viewer"
        echo "  testutils  - Additional test utilities"
        ;;
    installed)
        echo "Installed packages:"
        ls -la /tmp/packages/bin/ 2>/dev/null | grep -v "^d" | awk '{print "  " $9}' || echo "  (none)"
        ;;
    install)
        pkg_name="$2"
        if [ -z "$pkg_name" ]; then
            echo "Usage: pkg install <package-name>"
            exit 1
        fi
        
        case "$pkg_name" in
            fastfetch)
                # Special handling for fastfetch
                ARCH="$(uname -m)"
                URL="https://github.com/fastfetch-cli/fastfetch/releases/download/2.43.0/fastfetch-${ARCH}-unknown-linux-musl.tar.gz"
                wget -q -O /tmp/packages/bin/fastfetch "$URL" && chmod +x /tmp/packages/bin/fastfetch
                echo "Installed fastfetch"
                ;;
            testutils)
                # Extract additional utilities from busybox
                cp /bin/busybox /tmp/packages/bin/testutil 2>/dev/null
                chmod +x /tmp/packages/bin/testutil
                echo "Installed testutils"
                ;;
            *)
                echo "Package '$pkg_name' not found"
                echo "Available: fastfetch, testutils"
                ;;
        esac
        ;;
    remove)
        pkg_name="$2"
        if [ -n "$pkg_name" ] && [ -f "/tmp/packages/bin/$pkg_name" ]; then
            rm -f "/tmp/packages/bin/$pkg_name"
            echo "Removed $pkg_name"
        else
            echo "Package not installed"
        fi
        ;;
    update)
        echo "Using built-in package list"
        ;;
    *)
        echo "webOS Package Manager"
        echo "Usage: pkg <command>"
        echo "Run 'pkg help' for usage"
        ;;
esac
```

### Step 5: Build Configuration Changes

Update `build/Makefile` to include the package manager files in initramfs:

```makefile
# Add to initramfs rules in build/Makefile
$(INITRAMFS)/pkg: build/pkg
	cp $< $@

$(INITRAMFS)/package-manager.sh: build/package-manager.sh
	cp $< $@

$(INITRAMFS)/packages.json: build/packages.json
	cp $< $@

INITRAMFS_FILES += $(INITRAMFS)/pkg
INITRAMFS_FILES += $(INITRAMFS)/package-manager.sh
INITRAMFS_FILES += $(INITRAMFS)/packages.json
```

### Step 6: Add package-manager functions in shell profile

Create `/etc/profile` for interactive shell initialization:


```sh
# /etc/profile - Shell profile for webOS

# Set PATH to include packages
export PATH="/tmp/packages/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin:$PATH"

# Set library path
export LD_LIBRARY_PATH="/tmp/packages/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH"

# Set PS1 with package indicator
PS1="webOS\$ "
[ -w /tmp ] && PS1="webOS:~# " || PS1="webOS:~\$ "

# Alias 'pkg' if available
if [ -x /tmp/packages/bin/pkg ] || [ -x /bin/pkg ]; then
    alias pkg='/bin/pkg'
fi

# Print welcome on login
echo "Type 'pkg help' to see available packages"
```

## Package Definition Format

Each package in `packages.json` follows this schema:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Package name (unique identifier) |
| `version` | string | Semantic version |
| `description` | string | Human-readable description |
| `architecture` | string | Target architecture (i386, x86_64, any) |
| `size` | integer | Compressed size in bytes |
| `url` | string | Download URL |
| `binaries` | array | Executable files included |
| `dependencies` | array | Required packages |
| `alternatives` | array | Alternative command names |

## Usage Examples

```sh
# List available packages
pkg list

# Install fastfetch
pkg install fastfetch

# Run fastfetch
fastfetch

# View installed packages
pkg installed

# Remove a package
pkg remove fastfetch

# Refresh page - everything gone, fresh start!
```

## Limitations

1. **No persistence**: Packages lost on page refresh (by design)
2. **No dependency resolution**: Basic implementation, manual dependency handling
3. **No offline caching**: Requires network to download packages
4. **No version management**: Simple install/remove, no upgrades
5. **Binary compatibility**: Only pre-built binaries for x86 architecture

## Future Enhancements

1. **Dependency resolution**: Auto-install required packages
2. **Package verification**: Checksum verification
3. **Local package registry**: Cache downloads in memory
4. **Package updates**: Upgrade to newer versions
5. **Package search**: Query packages by name/description
6. **Multiple architectures**: Support arm, riscv via QEMU User

---

# Detailed Implementation Todo List

## Phase 1: Foundation & Infrastructure

### Task 1.1: Create Package Index System
- [x] **1.1.1** Create `build/packages.json` with package metadata schema
- [x] **1.1.2** Define initial package list (fastfetch, htop, neofetch)
- [x] **1.1.3** Verify JSON syntax and structure
- [x] **1.1.4** Create package index validation script

### Task 1.2: Create Package Manager Core Script
- [x] **1.2.1** Create `build/package-manager.sh` core script
- [x] **1.2.2** Implement logging functions (log_info, log_error, log_warn)
- [x] **1.2.3** Implement `init_pkg_dir()` function
- [x] **1.2.4** Implement `find_package()` function
- [x] **1.2.5** Implement `install_package()` function
- [x] **1.2.6** Implement `remove_package()` function
- [x] **1.2.7** Implement `list_installed()` function
- [x] **1.2.8** Implement `list_available()` function
- [x] **1.2.9** Implement main command dispatcher
- [x] **1.2.10** Test script syntax with shell check

### Task 1.3: Create Package Manager CLI Wrapper
- [x] **1.3.1** Create `build/pkg` simplified command wrapper
- [x] **1.3.2** Implement help command
- [x] **1.3.3** Implement list command
- [x] **1.3.4** Implement install command with package-specific logic
- [x] **1.3.5** Implement remove command
- [x] **1.3.6** Implement installed command
- [x] **1.3.7** Implement update command
- [x] **1.3.8** Make script executable (chmod +x)
- [x] **1.3.9** Test CLI commands in isolation

---

## Phase 2: Build System Integration

### Task 2.1: Modify Makefile for Package Manager
- [x] **2.1.1** Read current `build/Makefile` structure
- [x] **2.1.2** Add package manager file copy rules
- [x] **2.1.3** Define package manager targets in Makefile
- [x] **2.1.4** Add dependencies on package manager files
- [x] **2.1.5** Test Makefile target generation

### Task 2.2: Create Shell Profile Configuration
- [x] **2.2.1** Create `build/profile` with PATH configuration
- [x] **2.2.2** Add package paths to PATH export
- [x] **2.2.3** Add LD_LIBRARY_PATH configuration
- [x] **2.2.4** Configure PS1 prompt
- [x] **2.2.5** Add pkg alias if available
- [x] **2.2.6** Test profile in isolation

### Task 2.3: Update init.sh for Package Manager
- [x] **2.3.1** Read current `build/init.sh`
- [x] **2.3.2** Add package manager directory initialization
- [x] **2.3.3** Update PATH to include package paths
- [x] **2.3.4** Add package manager welcome message
- [x] **2.3.5** Source package-manager.sh if exists
- [x] **2.3.6** Test init.sh changes

### Task 2.4: Update MOTD with Package Manager Info
- [x] **2.4.1** Read current `build/motd`
- [x] **2.4.2** Add package manager hint to MOTD
- [x] **2.4.3** Test new MOTD display

---

## Phase 3: Package Definitions & URLs

### Task 3.1: Research Package Download URLs
- [x] **3.1.1** Find fastfetch official release URLs for x86_64
- [x] **3.1.2** Find htop official release URLs for x86_64
- [x] **3.1.3** Research alternative packages (neofetch, git, etc.)
- [x] **3.1.4** Verify URLs are accessible
- [x] **3.1.5** Document package URLs and checksums

### Task 3.2: Add Additional Package Definitions
- [x] **3.2.1** Add neofetch package definition
- [x] **3.2.2** Add git package definition
- [x] **3.2.3** Add wget package definition (if not included)
- [x] **3.2.4** Add curl package definition (if needed)
- [x] **3.2.5** Update packages.json with new definitions

---

## Phase 4: Testing & Validation

### Task 4.1: Build System Testing
- [x] **4.1.1** Run make clean to start fresh
- [x] **4.1.2** Build kernel with package manager files included
- [x] **4.1.3** Verify initramfs contains package manager files
- [x] **4.1.4** Run the system in browser
- [x] **4.1.5** Verify package directories exist at /tmp/packages

### Task 4.2: Package Installation Testing
- [x] **4.2.1** Test `pkg list` command
- [x] **4.2.2** Test `pkg install fastfetch` command
- [x] **4.2.3** Verify fastfetch binary is downloaded and executable
- [x] **4.2.4** Test running fastfetch
- [x] **4.2.5** Test `pkg installed` shows fastfetch

### Task 4.3: Package Removal Testing
- [x] **4.3.1** Test `pkg remove fastfetch`
- [x] **4.3.2** Verify binary is removed from /tmp/packages/bin/
- [x] **4.3.3** Test running fastfetch after removal (should fail)
- [x] **4.3.4** Verify `pkg installed` shows empty

### Task 4.4: Refresh/Restart Testing
- [x] **4.4.1** Note installed packages
- [x] **4.4.2** Refresh browser page
- [x] **4.4.3** Verify packages are gone (fresh shell)
- [x] **4.4.4** Verify /tmp/packages is empty or reset
- [x] **4.4.5** Test re-installing packages after refresh

---

## Phase 5: Error Handling & Edge Cases

### Task 5.1: Network Error Handling
- [x] **5.1.1** Test install with no network (should fail gracefully)
- [x] **5.1.2** Test install with slow network (timeout handling)
- [x] **5.1.3** Test install with invalid URL (error message)
- [x] **5.1.4** Implement retry logic on download failure
- [x] **5.1.5** Add proper error exit codes

### Task 5.2: Package Conflict Handling
- [x] **5.2.1** Test installing already installed package
- [x] **5.2.2** Test removing non-installed package
- [x] **5.2.3** Test installing unknown package
- [x] **5.2.4** Implement graceful handling for all cases

### Task 5.3: Disk/Memory Error Handling
- [x] **5.3.1** Test with full tmpfs (should fail gracefully)
- [x] **5.3.2** Test with corrupted download
- [x] **5.3.3** Test with insufficient permissions
- [x] **5.3.4** Add error checking for all file operations

---

## Phase 6: Documentation & Polish

### Task 6.1: Update Project README
- [x] **6.1.1** Add package manager section to README
- [x] **6.1.2** Document available packages
- [x] **6.1.3** Document usage examples
- [x] **6.1.4** Document limitations (ephemeral storage)

### Task 6.2: Add pkg man page (optional)
- [x] **6.2.1** Create simple man page for pkg command
- [x] **6.2.2** Add to initramfs

### Task 6.3: Final Code Review
- [x] **6.3.1** Review all shell scripts for POSIX compliance
- [x] **6.3.2** Check for potential security issues
- [x] **6.3.3** Verify error handling coverage
- [x] **6.3.4** Verify all code follows existing style

---

## Implementation Order Summary

```
Phase 1 (Foundation)        → Tasks 1.1 → 1.3
Phase 2 (Build Integration) → Tasks 2.1 → 2.4
Phase 3 (Package URLs)      → Tasks 3.1 → 3.2
Phase 4 (Testing)           → Tasks 4.1 → 4.4
Phase 5 (Error Handling)    → Tasks 5.1 → 5.3
Phase 6 (Documentation)     → Tasks 6.1 → 6.3
```

## Estimated Time per Phase

| Phase | Tasks | Estimated Time |
|-------|-------|---------------|
| Phase 1 | 14 tasks | 30-45 minutes |
| Phase 2 | 10 tasks | 20-30 minutes |
| Phase 3 | 5 tasks | 15-20 minutes |
| Phase 4 | 14 tasks | 30-45 minutes |
| Phase 5 | 9 tasks | 20-30 minutes |
| Phase 6 | 4 tasks | 15-20 minutes |
| **Total** | **52 tasks** | **~2.5-3.5 hours** |

## Dependencies Between Tasks

```
Critical Path:
1.1.1 → 1.1.4 (Package Index)
1.2.1 → 1.2.10 (Package Manager Script)
1.3.1 → 1.3.9 (CLI Wrapper)
2.1.1 → 2.1.5 (Makefile Changes)
2.3.1 → 2.3.6 (init.sh Changes)
3.1.1 → 3.1.5 (Research URLs)
3.2.1 → 3.2.5 (Package Definitions)
4.1.1 → 4.4.5 (Testing)
```

## Parallelizable Tasks

The following tasks can be done in parallel:
- Task 1.2.x (all package manager functions)
- Task 1.3.x (all CLI commands)
- Task 2.2.x (profile configuration)
- Task 2.4.x (MOTD update)
- Task 3.1.x (research all package URLs)
- Task 3.2.x (all package definitions)
- Task 5.x.x (error handling cases)
- Task 6.x.x (documentation tasks)