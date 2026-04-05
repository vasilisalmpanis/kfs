NAME				= $(KFS_FULL)
KERNEL				= zig-out/bin/kfs.bin

SRC_DIR				= src
BOOT_DIR			= boot
BOOT_GRUB_DIR		= $(BOOT_DIR)/grub
GRUB_CFG			= $(BOOT_GRUB_DIR)/grub.cfg

MOD_SRC_DIR			= modules
MODULES				= example keyboard time

ROOTFS_FULL_DIR		= rootfs_full
ROOTFS_MIN_DIR		= rootfs_min

ROOTFS_FULL_IMG		= $(BUILD_DIR)/rootfs-full.img
ROOTFS_MIN_IMG		= $(BUILD_DIR)/rootfs-min.img
ROOTFS_IMG	    	= $(ROOTFS_FULL_IMG)

ROOTFS_BASE_URI		= https://github.com/vasilisalmpanis/kfs/releases/download/filesystem
ROOTFS_MIN_TAR		= rootfs_min.tar.gz
ROOTFS_FULL_TAR		= rootfs_full.tar.gz
ROOTFS_MIN_TAR_URI	= $(ROOTFS_BASE_URI)/$(ROOTFS_MIN_TAR)
ROOTFS_FULL_TAR_URI	= $(ROOTFS_BASE_URI)/$(ROOTFS_FULL_TAR)

BUILD_DIR			= release/build
RELEASE_DIR			= release/dist

# === Artifacts ===
KFS_MIN				= $(RELEASE_DIR)/kfs-min.img
KFS_FULL			= $(RELEASE_DIR)/kfs-full.img
KERNEL_BOOT_IMAGE	= $(RELEASE_DIR)/kfs-kernel.iso
KERNEL_ARTIFACT		= $(RELEASE_DIR)/kfs.bin

MOD_TARGET_DIR		= $(ROOTFS_FULL_DIR)/modules

# === Sources ===
SRC		= $(shell find $(SRC_DIR) -name '*.zig')
ASM_SRC	= $(shell find $(SRC_DIR) -name '*.s')

# === Tool Detection ===
QEMU := $(shell \
	if command -v qemu-system-i386 >/dev/null 2>&1; then \
		echo qemu-system-i386; \
	elif command -v qemu-system-x86_64 >/dev/null 2>&1; then \
		echo qemu-system-x86_64; \
	else \
		echo qemu-system-i386; \
	fi)

OS = linux
ifeq ($(shell uname -s),Darwin)
	OS = macos
endif

KVM := $(shell \
	if command -v lsmod >/dev/null 2>&1 && lsmod | grep kvm >/dev/null 2>&1; then \
		echo -enable-kvm; \
	else \
		echo; \
	fi)

ifeq ($(OS),macos)
	KVM =
endif

all: $(NAME)

build-image: $(NAME)

$(KERNEL): $(SRC) $(ASM_SRC)
	zig build -freference-trace=20

# === Rootfs Preparation ===
$(ROOTFS_FULL_DIR): $(ROOTFS_FULL_TAR) | $(BUILD_DIR)
	$(shell [ ! -d $(ROOTFS_FULL_DIR) ] && \
		tar -xf $(ROOTFS_FULL_TAR) \
	)
	touch $(ROOTFS_FULL_DIR)

$(ROOTFS_MIN_DIR): $(ROOTFS_MIN_TAR) | $(BUILD_DIR)
	$(shell [ ! -d $(ROOTFS_MIN_DIR) ] && \
		tar -xf $(ROOTFS_MIN_TAR) \
	)
	touch $(ROOTFS_MIN_DIR)

prepare-rootfs: $(ROOTFS_FULL_DIR)

$(ROOTFS_FULL_TAR):
	wget $(ROOTFS_FULL_TAR_URI)

$(ROOTFS_MIN_TAR):
	wget $(ROOTFS_MIN_TAR_URI)

modules: $(addprefix $(MOD_TARGET_DIR)/,$(MODULES:=.o))

.SECONDEXPANSION:
$(MOD_TARGET_DIR)/%.o: \
	$$(shell find $(MOD_SRC_DIR)/$$*/ -type f -name '*.zig' 2>/dev/null) \
	| $(MOD_TARGET_DIR)
	zig build \
		--build-file $(MOD_SRC_DIR)/$*/build.zig \
		-p $(MOD_TARGET_DIR)
	touch $@

$(MOD_TARGET_DIR): $(ROOTFS_FULL_DIR)
	@mkdir -p $(MOD_TARGET_DIR)

$(ROOTFS_FULL_IMG): $(ROOTFS_FULL_DIR) $(addprefix $(MOD_TARGET_DIR)/,$(MODULES:=.o))
	@mkdir -p $(dir $(ROOTFS_FULL_IMG))
	yes | mke2fs -L '' -N 0 -O ^64bit \
		-d $(ROOTFS_FULL_DIR) \
		-m 5 -r 1 \
		-t ext2 \
		-b 8192 \
		$(ROOTFS_FULL_IMG) \
		$$(du -s $(ROOTFS_FULL_DIR) | awk '{print int($$1 * 1.1) + 10240 "K"}')

$(ROOTFS_MIN_IMG): $(ROOTFS_MIN_DIR)
	@mkdir -p $(dir $(ROOTFS_MIN_IMG))
	yes | mke2fs -L '' -N 0 -O ^64bit \
		-d $(ROOTFS_MIN_DIR) \
		-m 5 -r 1 \
		-t ext2 \
		-b 8192 \
		$(ROOTFS_MIN_IMG) \
		$$(du -s $(ROOTFS_MIN_DIR) | awk '{print int($$1 * 1.1) + 1024 "K"}')

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(RELEASE_DIR):
	@mkdir -p $(RELEASE_DIR)

# === Releases ===
$(KFS_FULL): $(KERNEL) $(GRUB_CFG) $(ROOTFS_FULL_IMG) | $(BUILD_DIR) $(RELEASE_DIR)
	@mkdir -p $(dir $(KFS_FULL))
	DISK=$(KFS_FULL) KERNEL=$(KERNEL) ROOT_IMG=$(ROOTFS_FULL_IMG) GRUB_CFG=$(GRUB_CFG) \
	sh scripts/create_boot_disk.sh $(KFS_FULL)

release-full: $(KFS_FULL)

$(KFS_MIN): $(KERNEL) $(GRUB_CFG) $(ROOTFS_MIN_IMG) | $(BUILD_DIR) $(RELEASE_DIR)
	@mkdir -p $(dir $(KFS_MIN))
	DISK=$(KFS_MIN) KERNEL=$(KERNEL) ROOT_IMG=$(ROOTFS_MIN_IMG) GRUB_CFG=$(GRUB_CFG) \
	sh scripts/create_boot_disk.sh $(KFS_MIN)

release-min: $(KFS_MIN)

release-kernel: $(KERNEL) | $(RELEASE_DIR)
	cp $(KERNEL) $(KERNEL_ARTIFACT)

release-all: release-full release-min release-kernel

# === Runtime ===
qemu: $(NAME)
	$(QEMU) $(KVM) \
		-drive file=$(NAME),format=raw \
		-serial stdio \
		-serial pty \
		-m 4G

debug: $(NAME)
	$(QEMU) -drive file=$(NAME),format=raw \
		-m 1G \
		-s -S &
	gdb $(KERNEL) -ex "target remote localhost:1234" \
		-ex "layout split src asm" \
		-ex "b kernel_main" \
		-ex "c"

clean:
	rm -f $(ROOTFS_IMG) $(NAME)
	rm -rf zig-out
	rm -rf $(BUILD_DIR)

fclean: clean
	rm -rf $(NAME)
	rm -rf $(RELEASE_DIR)
	rm -rf .zig-cache
	rm -f $(ROOTFS_MIN_TAR) $(ROOTFS_FULL_TAR)

# === Package Lists ===
APT_PACKAGES	?= zig grub-pc-bin grub-common xorriso qemu-system-x86 mtools e2fsprogs gdisk wget python3 make
DNF_PACKAGES	?= zig grub2-pc grub2-tools grub2-tools-extra xorriso qemu-system-x86 mtools e2fsprogs gdisk wget python3 make
PACMAN_PACKAGES	?= zig grub xorriso qemu-system-x86 mtools e2fsprogs gptfdisk wget python make
APK_PACKAGES	?= zig grub grub-bios xorriso qemu-system-i386 mtools e2fsprogs gptfdisk wget python3 make
BREW_PACKAGES	?= zig i686-elf-grub qemu xorriso mtools e2fsprogs gptfdisk wget

# === Tooling ===
check-tools:
	@ok=1; \
	for cmd in zig make wget tar python3 mke2fs sgdisk; do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "missing: $$cmd"; \
			ok=0; \
		fi; \
	done; \
	if	! command -v grub-mkimage >/dev/null 2>&1 \
		&& ! command -v grub2-mkimage >/dev/null 2>&1 \
		&& ! command -v i686-elf-grub-mkimage >/dev/null 2>&1; then \
			echo "missing: grub-mkimage (or grub2-mkimage or i686-elf-grub-mkimage)"; \
			ok=0; \
	fi; \
	if	! command -v qemu-system-i386 >/dev/null 2>&1 \
		&& ! command -v qemu-system-x86_64 >/dev/null 2>&1; then \
			echo "missing: qemu-system-i386 (or qemu-system-x86_64)"; \
			ok=0; \
	fi; \
	if [ $$ok -eq 1 ]; then \
		echo "All required tools found"; \
	else \
		exit 1; \
	fi

tools-linux-apt:
	apt update
	apt install -y $(APT_PACKAGES)

tools-linux-dnf:
	dnf install -y $(DNF_PACKAGES)

tools-linux-pacman:
	pacman -Sy --noconfirm $(PACMAN_PACKAGES)

tools-linux-apk:
	apk add --no-cache $(APK_PACKAGES)

tools-linux-root:
	@if command -v apt >/dev/null 2>&1; then \
		$(MAKE) tools-linux-apt; \
	elif command -v dnf >/dev/null 2>&1; then \
		$(MAKE) tools-linux-dnf; \
	elif command -v pacman >/dev/null 2>&1; then \
		$(MAKE) tools-linux-pacman; \
	elif command -v apk >/dev/null 2>&1; then \
		$(MAKE) tools-linux-apk; \
	else \
		echo "Unsupported distro package manager. Install dependencies manually, then run: make check-tools"; \
		exit 1; \
	fi

tools-user-brew:
	brew install $(BREW_PACKAGES)

install-tools-user:
	@if command -v brew >/dev/null 2>&1; then \
		$(MAKE) tools-user-brew; \
	else \
		echo "No rootless installer found (brew or nix)."; \
		echo "Use system installer (make install-tools-system) or install manually and run make check-tools."; \
		exit 1; \
	fi

install-tools-system:
	@if [ "$(OS)" = "macos" ]; then \
		$(MAKE) tools-user-brew; \
	else \
		if [ "$$(id -u)" -eq 0 ]; then \
			$(MAKE) tools-linux-root; \
		elif command -v sudo >/dev/null 2>&1; then \
			sudo $(MAKE) tools-linux-root; \
		else \
			echo "No root privileges and no sudo. Use make install-tools-user"; \
			exit 1; \
		fi; \
	fi

install-tools:
	@$(MAKE) check-tools >/dev/null 2>&1 && { echo "All required tools already installed"; exit 0; } || true
	@if [ "$(OS)" = "macos" ]; then \
		$(MAKE) tools-user-brew; \
	else \
		if command -v brew >/dev/null 2>&1; then \
			$(MAKE) install-tools-user; \
		else \
			$(MAKE) install-tools-system; \
		fi; \
	fi
	@$(MAKE) check-tools

.PHONY: all clean fclean qemu debug modules build-image \
	prepare-rootfs \
	release-full release-min release-kernel release-all \
	check-tools \
	tools-linux-apt tools-linux-dnf tools-linux-pacman \
	tools-linux-apk tools-linux-root tools-user-brew \
	install-tools-user install-tools-system install-tools
