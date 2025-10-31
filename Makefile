NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso
SRC_DIR = src
USERSPACE_DIR = userspace

IMG 		= ext2.img
IMG_DIR		= ext2_dir
IMG_SIZE	= 32M

MOD_SRC_DIR		= modules
MOD_TARGET_DIR	= $(IMG_DIR)/modules

MODULES = example keyboard time

GPT_DISK = disk/disk.img

OS = linux
ifeq ($(shell uname -s),Darwin)
	OS = macos
endif

SRC = $(shell find $(SRC_DIR) -name '*.zig')
SRC += $(shell find $(USERSPACE_DIR) -name '*.zig')
ASM_SRC = $(shell find $(SRC_DIR) -name '*.s')
GRUB_CFG = $(ISO_DIR)/boot/grub/grub.cfg
QEMU = qemu-system-i386

MKRESCUE = grub-mkrescue
KVM = -enable-kvm
ifeq ($(OS),macos)
	MKRESCUE = i686-elf-grub-mkrescue
	KVM = 
endif

all: $(NAME)

$(NAME): $(KERNEL) $(GRUB_CFG)
	cp $(KERNEL) $(ISO_DIR)/boot/
	$(MKRESCUE) --compress=xz -o $(NAME) $(ISO_DIR)

$(KERNEL): $(SRC) $(ASM_SRC)
	zig build -freference-trace=20 # -Doptimize=ReleaseSafe

clean:
	rm -f $(IMG)
	rm -rf zig-out $(ISO_DIR)/boot/kfs.bin
	rm -rf $(MOD_TARGET_DIR)/*

fclean: clean
	rm -rf $(NAME)
	rm -rf .zig-cache

qemu: $(NAME) $(IMG)
	$(QEMU) $(KVM) \
		-cdrom $(NAME) \
		-serial stdio \
		-m 4G \
		-drive file=$(IMG),format=raw \
		-drive file=$(GPT_DISK),format=raw

debug: $(NAME) $(IMG)
	$(QEMU) -cdrom $(NAME) \
	-m 1G \
	-drive file=$(IMG),format=raw \
	-s -S &
	gdb $(KERNEL) -ex "target remote localhost:1234" \
		-ex "layout split src asm" \
		-ex "b kernel_main" \
		-ex "c"

brew:
	brew install \
		zig i686-elf-grub \
		qemu xorriso \
		mtools e2fsprogs

.SECONDEXPANSION:
$(IMG): $(addprefix $(MOD_TARGET_DIR)/,$(MODULES:=.o)) \
	$$(shell [ -d $(IMG_DIR) ] && \
        find -L $(IMG_DIR) -mindepth 1 \( -type f -o -type d \) 2>/dev/null) \
	| $(IMG_DIR)
	yes | mke2fs -L '' -N 0 -O ^64bit \
		-d $(IMG_DIR) \
		-m 5 -r 1 \
		-t ext2 \
		-b 1024 \
		$(IMG) \
		$(IMG_SIZE)

$(IMG_DIR):
	mkdir -p $(IMG_DIR)
	mkdir -p $(IMG_DIR)/bin
	mkdir -p $(IMG_DIR)/modules
	mkdir -p $(IMG_DIR)/dev
	mkdir -p $(IMG_DIR)/etc
	mkdir -p $(IMG_DIR)/home
	mkdir -p $(IMG_DIR)/sys
	mkdir -p $(IMG_DIR)/tmp
	mkdir -p $(IMG_DIR)/var

modules: $(addprefix $(MOD_TARGET_DIR)/,$(MODULES:=.o))

.SECONDEXPANSION:
$(MOD_TARGET_DIR)/%.o: \
	$$(shell find $(MOD_SRC_DIR)/$$*/ -type f -name '*.zig' 2>/dev/null) \
	| $(MOD_TARGET_DIR)
	zig build \
		--build-file $(MOD_SRC_DIR)/$*/build.zig \
		-p $(MOD_TARGET_DIR)
	touch $@

$(MOD_TARGET_DIR): $(IMG_DIR)

.PHONY: all clean qemu modules brew
