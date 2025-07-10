NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso
SRC_DIR = src
USERSPACE_DIR = userspace

IMG 	= ext2.img
IMG_DIR = ext2_dir

SRC = $(shell find $(SRC_DIR) -name '*.zig')
SRC += $(shell find $(USERSPACE_DIR) -name '*.zig')
ASM_SRC = $(shell find $(SRC_DIR) -name '*.s')
GRUB_CFG = $(ISO_DIR)/boot/grub/grub.cfg
MKRESCUE = grub-mkrescue

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
	qemu-system-i386 \
		-enable-kvm \
		-cdrom $(NAME) \
		-serial stdio \
		-drive file=${IMG},format=raw

debug: $(NAME)
	qemu-system-i386 -cdrom $(NAME) -s -S &
	gdb $(KERNEL) -ex "target remote localhost:1234" \
		-ex "layout split src asm" \
		-ex "b kernel_main" \
		-ex "c"

multimonitor: $(NAME)
	qemu-system-i386 -enable-kvm -device virtio-vga,max_outputs=2 -cdrom $(NAME) -serial stdio

$(IMG):
	mke2fs -L '' -N 0 -O ^64bit -d ${IMG_DIR} -m 5 -r 1 -t ext2 ${IMG} 32M

.PHONY: all clean qemu multimonitor
