NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso
SRC_DIR = src
USERSPACE_DIR = userspace

IMG 	= ext2.img
IMG_DIR = ext2_dir

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
	rm -f ${IMG}
	rm -rf zig-out $(ISO_DIR)/boot/kfs.bin

fclean: clean
	rm -rf $(NAME)
	rm -rf .zig-cache

qemu: $(NAME) $(IMG)
	$(QEMU) $(KVM) \
		-cdrom $(NAME) \
		-serial stdio \
		-drive file=${IMG},format=raw \
		-drive file=${GPT_DISK},format=raw

debug: $(NAME)
	$(QEMU) -cdrom $(NAME) -s -S &
	gdb $(KERNEL) -ex "target remote localhost:1234" \
		-ex "layout split src asm" \
		-ex "b kernel_main" \
		-ex "c"

multimonitor: $(NAME)
	$(QEMU) -enable-kvm -device virtio-vga,max_outputs=2 -cdrom $(NAME) -serial stdio

brew:
	brew install \
		zig i686-elf-grub \
		qemu xorriso \
		mtools e2fsprogs

$(IMG):
	mke2fs -L '' -N 0 -O ^64bit -d ${IMG_DIR} -m 5 -r 1 -t ext2 -b 1024 ${IMG} 32M

.PHONY: all clean qemu multimonitor brew
