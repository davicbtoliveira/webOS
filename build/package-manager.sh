#!/bin/sh
PKG_DIR="/tmp/packages"
PKG_DB="/tmp/packages.db"
PACKAGES_JSON="/etc/packages.json"
WGET_OPTS="-q --timeout=30"
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

init_pkg_dir() {
    mkdir -p "$PKG_DIR/bin"
    mkdir -p "$PKG_DIR/lib"
    mkdir -p "$PKG_DIR/etc"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/lib"
    ln -sf "$PKG_DIR/bin" /usr/local/bin 2>/dev/null || true
    ln -sf "$PKG_DIR/lib" /usr/local/lib 2>/dev/null || true
    ln -sf "$PKG_DIR" /usr/local/packages 2>/dev/null || true
}

install_package() {
    local pkg_name="$1"
    local pkg_url pkg_binaries pkg_version

    log_info "Installing $pkg_name..."

    if [ -f "$PKG_DIR/bin/$pkg_name" ]; then
        log_warn "$pkg_name is already installed"
        return 1
    fi

    case "$pkg_name" in
        fastfetch)
            pkg_version="2.43.0"
            ARCH="$(uname -m)"
            if [ "$ARCH" = "x86_64" ]; then
                pkg_url="https://github.com/fastfetch-cli/fastfetch/releases/download/${pkg_version}/fastfetch-${ARCH}-unknown-linux-musl.tar.gz"
            else
                pkg_url="https://github.com/fastfetch-cli/fastfetch/releases/download/${pkg_version}/fastfetch-x86_64-unknown-linux-musl.tar.gz"
            fi
            pkg_binaries="fastfetch"
            ;;
        htop)
            pkg_version="3.3.0"
            pkg_url="https://github.com/htop-dev/htop/releases/download/${pkg_version}/htop-${pkg_version}.tar.gz"
            pkg_binaries="htop"
            ;;
        neofetch)
            pkg_version="7.1.0"
            pkg_url="https://github.com/dylanaraps/neofetch/releases/download/${pkg_version}/neofetch-${pkg_version}.tar.gz"
            pkg_binaries="neofetch"
            ;;
        *)
            log_error "Package '$pkg_name' not found"
            return 1
            ;;
    esac

    local tmp_dir="/tmp/install.$pkg_name.$$"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"

    log_info "Downloading $pkg_name..."
    if ! wget $WGET_OPTS "$pkg_name.tar.gz" "$pkg_url" 2>/dev/null; then
        wget $WGET_OPTS -O "$pkg_name.tar.gz" "$pkg_url" || {
            log_error "Failed to download $pkg_name"
            rm -rf "$tmp_dir"
            return 1
        }
    fi

    if [ ! -f "$pkg_name.tar.gz" ]; then
        log_error "Download failed"
        rm -rf "$tmp_dir"
        return 1
    fi

    log_info "Extracting..."
    tar -xzf "$pkg_name.tar.gz" 2>/dev/null || tar -xf "$pkg_name.tar.gz" 2>/dev/null || {
        log_error "Failed to extract"
        rm -rf "$tmp_dir"
        return 1
    }

    local extracted_dir
    extracted_dir=$(ls -d */ 2>/dev/null | head -1)
    if [ -n "$extracted_dir" ]; then
        cd "$extracted_dir"
        for bin in $pkg_binaries; do
            if [ -f "$bin" ]; then
                cp "$bin" "$PKG_DIR/bin/"
                chmod +x "$PKG_DIR/bin/$bin"
                log_info "Installed $bin"
            fi
        done
        for lib in *.so*; do
            [ -f "$lib" ] && cp "$lib" "$PKG_DIR/lib/"
        done
    fi

    cd /
    rm -rf "$tmp_dir"

    log_info "$pkg_name installed successfully"
    return 0
}

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

list_installed() {
    log_info "Installed packages:"
    found=0
    for pkg in "$PKG_DIR/bin/"*; do
        if [ -f "$pkg" ]; then
            printf "  %s\n" "$(basename "$pkg")"
            found=1
        fi
    done
    [ "$found" -eq 0 ] && printf "  (none)\n"
}

list_available() {
    log_info "Available packages:"
    printf "  fastfetch  - Fast fetch system information tool\n"
    printf "  htop      - Interactive process viewer\n"
    printf "  neofetch  - System information fetch tool (ASCII art)\n"
}

main() {
    local command="$1"
    shift

    init_pkg_dir
    export PATH="/tmp/packages/bin:/usr/local/bin:$PATH"
    export LD_LIBRARY_PATH="/tmp/packages/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH"

    case "$command" in
        install)
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
            echo "  remove <package>    Remove a package"
            echo "  list                List available packages"
            echo "  list-installed      List installed packages"
            echo "  init                Initialize package directory"
            ;;
        *)
            if [ -n "$command" ]; then
                log_error "Unknown command: $command"
            fi
            echo "Use 'pkg help' for usage"
            ;;
    esac
}

main "$@"