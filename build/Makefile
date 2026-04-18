KERNEL_VERSION := 6.6.63
BUSYBOX_VERSION := 1.36.1

KERNEL_TARBALL := linux-$(KERNEL_VERSION).tar.xz
BUSYBOX_TARBALL := busybox-$(BUSYBOX_VERSION).tar.bz2

KERNEL_URL := https://cdn.kernel.org/pub/linux/kernel/v6.x/$(KERNEL_TARBALL)
BUSYBOX_URL := https://busybox.net/downloads/$(BUSYBOX_TARBALL)

V86_BASE := https://copy.sh/v86

XTERM_VERSION := 5.3.0
XTERM_JS := https://cdn.jsdelivr.net/npm/xterm@$(XTERM_VERSION)/lib/xterm.js
XTERM_CSS := https://cdn.jsdelivr.net/npm/xterm@$(XTERM_VERSION)/css/xterm.css
XTERM_FIT := https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js

ROOT := $(abspath $(CURDIR)/..)
BUILD := $(ROOT)/build
SRC := $(ROOT)/src
DIST := $(ROOT)/dist
WEB := $(ROOT)/web
IMAGES := $(WEB)/images

KERNEL_DIR := $(SRC)/linux-$(KERNEL_VERSION)
BUSYBOX_DIR := $(SRC)/busybox-$(BUSYBOX_VERSION)
INITRAMFS := $(BUILD)/initramfs

NPROC := $(shell nproc)

.PHONY: all fetch kernel busybox initramfs web clean distclean deps-check run shim

all: deps-check $(IMAGES)/bzImage $(WEB)/vendor/libv86.js $(WEB)/vendor/xterm.js

shim: $(BUILD)/shim/i686-linux-gnu-ld $(BUILD)/shim/i686-linux-gnu-ar \
      $(BUILD)/shim/i686-linux-gnu-strip $(BUILD)/shim/i686-linux-gnu-nm \
      $(BUILD)/shim/i686-linux-gnu-objcopy $(BUILD)/shim/i686-linux-gnu-objdump \
      $(BUILD)/shim/i686-linux-gnu-ranlib

$(BUILD)/shim/i686-linux-gnu-%:
	@mkdir -p $(BUILD)/shim
	@if command -v i686-linux-gnu-$* >/dev/null 2>&1; then \
		ln -sf "$$(command -v i686-linux-gnu-$*)" $@; \
	else \
		ln -sf "$$(command -v $*)" $@; \
	fi

deps-check:
	@for t in gcc make bison flex bc curl xz; do \
		command -v $$t >/dev/null 2>&1 || { echo "missing: $$t"; exit 1; }; \
	done
	@echo "deps ok"

# ----- fetch -----

fetch: $(SRC)/$(KERNEL_TARBALL) $(SRC)/$(BUSYBOX_TARBALL)

$(SRC)/$(KERNEL_TARBALL):
	@mkdir -p $(SRC)
	curl -L -o $@ $(KERNEL_URL)

$(SRC)/$(BUSYBOX_TARBALL):
	@mkdir -p $(SRC)
	curl -L -o $@ $(BUSYBOX_URL)

$(KERNEL_DIR)/Makefile: $(SRC)/$(KERNEL_TARBALL)
	tar -C $(SRC) -xf $<
	@# GCC 15 (C23 default) breaks `typedef _Bool bool;` in boot/compressed;
	@# force -std=gnu11 in the 2 Makefiles that reset KBUILD_CFLAGS.
	sed -i '/^KBUILD_CFLAGS\s*:=.*_SETUP/a KBUILD_CFLAGS\t+= -std=gnu11 -Wno-error' $(KERNEL_DIR)/arch/x86/boot/Makefile
	sed -i '/^KBUILD_CFLAGS := -m\$$(BITS)/a KBUILD_CFLAGS += -std=gnu11 -Wno-error' $(KERNEL_DIR)/arch/x86/boot/compressed/Makefile
	touch $@

$(BUSYBOX_DIR)/Makefile: $(SRC)/$(BUSYBOX_TARBALL)
	tar -C $(SRC) -xf $<
	touch $@

# ----- busybox -----

busybox: $(INITRAMFS)/bin/busybox

$(BUSYBOX_DIR)/.config: $(BUILD)/busybox.fragment $(BUSYBOX_DIR)/Makefile
	$(MAKE) -C $(BUSYBOX_DIR) defconfig
	sed -i \
		-e 's/^CONFIG_TC=.*/# CONFIG_TC is not set/' \
		-e 's/^CONFIG_FEATURE_TC_INGRESS=.*/# CONFIG_FEATURE_TC_INGRESS is not set/' \
		-e 's/^CONFIG_FSFREEZE=.*/# CONFIG_FSFREEZE is not set/' \
		-e 's/^# CONFIG_STATIC .*/CONFIG_STATIC=y/' \
		$@
	cat $(BUILD)/busybox.fragment >> $@
	yes "" | $(MAKE) -C $(BUSYBOX_DIR) oldconfig >/dev/null
	grep -q '^CONFIG_STATIC=y' $@ || { echo "CONFIG_STATIC not enabled"; exit 1; }

$(BUSYBOX_DIR)/busybox: $(BUSYBOX_DIR)/.config shim
	PATH=$(BUILD)/shim:$$PATH $(MAKE) -C $(BUSYBOX_DIR) -j$(NPROC) \
		HOSTCC=gcc \
		CROSS_COMPILE=i686-linux-gnu- \
		EXTRA_CFLAGS="-Wno-error -Wno-unused-variable -Wno-discarded-qualifiers -Wno-deprecated-declarations -Wno-dangling-pointer" \
		CONFIG_PREFIX=$(INITRAMFS)

$(INITRAMFS)/bin/busybox: $(BUSYBOX_DIR)/busybox
	PATH=$(BUILD)/shim:$$PATH $(MAKE) -C $(BUSYBOX_DIR) \
		CROSS_COMPILE=i686-linux-gnu- CONFIG_PREFIX=$(INITRAMFS) install
	@file $(INITRAMFS)/bin/busybox | grep -q "statically linked" || { echo "not static!"; exit 1; }
	@file $(INITRAMFS)/bin/busybox | grep -q "Intel 80386\|Intel i386" || { echo "not 32-bit i386!"; exit 1; }

# ----- initramfs structure -----

initramfs: $(INITRAMFS)/init $(INITRAMFS)/etc/inittab $(INITRAMFS)/etc/motd $(INITRAMFS)/etc/profile $(INITRAMFS)/bin/busybox

$(INITRAMFS)/init: $(BUILD)/init.sh
	@mkdir -p $(INITRAMFS)
	install -m 755 $(BUILD)/init.sh $@

$(INITRAMFS)/etc/inittab: $(BUILD)/inittab
	@mkdir -p $(INITRAMFS)/etc
	install -m 644 $(BUILD)/inittab $@

$(INITRAMFS)/etc/motd: $(BUILD)/motd
	@mkdir -p $(INITRAMFS)/etc
	install -m 644 $(BUILD)/motd $@

$(INITRAMFS)/etc/profile: $(BUILD)/profile
	@mkdir -p $(INITRAMFS)/etc
	install -m 644 $(BUILD)/profile $@

# ----- kernel -----

kernel: $(IMAGES)/bzImage

$(BUILD)/shim/bc: $(INITRAMFS)/bin/busybox
	@mkdir -p $(BUILD)/shim
	ln -sf $(INITRAMFS)/bin/busybox $(BUILD)/shim/bc
	@echo 'bc shim ready'

$(KERNEL_DIR)/.config: $(BUILD)/kernel.fragment $(KERNEL_DIR)/Makefile $(BUILD)/shim/bc shim
	PATH=$(BUILD)/shim:$$PATH $(MAKE) -C $(KERNEL_DIR) ARCH=i386 CROSS_COMPILE=i686-linux-gnu- tinyconfig
	cat $(BUILD)/kernel.fragment >> $@
	@echo 'CONFIG_INITRAMFS_SOURCE="$(INITRAMFS)"' >> $@
	PATH=$(BUILD)/shim:$$PATH $(MAKE) -C $(KERNEL_DIR) ARCH=i386 CROSS_COMPILE=i686-linux-gnu- olddefconfig

$(KERNEL_DIR)/arch/x86/boot/bzImage: $(KERNEL_DIR)/.config initramfs
	PATH=$(BUILD)/shim:$$PATH $(MAKE) -C $(KERNEL_DIR) -j$(NPROC) ARCH=i386 \
		KBUILD_BUILD_USER=webos KBUILD_BUILD_HOST=builder \
		KBUILD_BUILD_TIMESTAMP="$$(date -u '+%Y-%m-%d %H:%M UTC')" \
		KCFLAGS="-std=gnu11 -Wno-error" bzImage

$(IMAGES)/bzImage: $(KERNEL_DIR)/arch/x86/boot/bzImage
	@mkdir -p $(IMAGES) $(DIST)
	cp $< $(DIST)/bzImage
	cp $< $@

# ----- web vendor -----

web: $(WEB)/vendor/libv86.js $(WEB)/vendor/xterm.js

$(WEB)/vendor/libv86.js:
	@mkdir -p $(WEB)/vendor $(IMAGES)
	curl -fL -o $(WEB)/vendor/libv86.js $(V86_BASE)/build/libv86.js
	curl -fL -o $(WEB)/vendor/v86.wasm $(V86_BASE)/build/v86.wasm
	curl -fL -o $(IMAGES)/seabios.bin $(V86_BASE)/bios/seabios.bin
	curl -fL -o $(IMAGES)/vgabios.bin $(V86_BASE)/bios/vgabios.bin

$(WEB)/vendor/xterm.js:
	@mkdir -p $(WEB)/vendor
	curl -fL -o $(WEB)/vendor/xterm.js $(XTERM_JS)
	curl -fL -o $(WEB)/vendor/xterm.css $(XTERM_CSS)
	curl -fL -o $(WEB)/vendor/xterm-addon-fit.js $(XTERM_FIT)

# ----- run -----

run:
	@command -v qemu-system-i386 >/dev/null || { echo "install qemu-system-x86"; exit 1; }
	qemu-system-i386 -kernel $(DIST)/bzImage -append "console=ttyS0 quiet" -nographic -no-reboot

serve:
	@echo "Open http://localhost:8000/"
	cd $(WEB) && python3 -m http.server 8000

# ----- clean -----

clean:
	rm -rf $(INITRAMFS)/bin $(INITRAMFS)/sbin $(INITRAMFS)/usr $(INITRAMFS)/linuxrc
	-$(MAKE) -C $(KERNEL_DIR) clean 2>/dev/null || true
	-$(MAKE) -C $(BUSYBOX_DIR) clean 2>/dev/null || true

distclean:
	rm -rf $(SRC) $(DIST) $(INITRAMFS)/bin $(INITRAMFS)/sbin $(INITRAMFS)/usr $(INITRAMFS)/linuxrc
	rm -f $(IMAGES)/bzImage $(IMAGES)/seabios.bin $(IMAGES)/vgabios.bin
	rm -rf $(WEB)/vendor
