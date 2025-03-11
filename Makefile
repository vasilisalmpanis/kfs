NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso
SRC_DIR = src

SRC = $(shell find $(SRC_DIR) -name '*.zig')
ASM_SRC = $(shell find $(SRC_DIR) -name '*.s')
GRUB_CFG = $(ISO_DIR)/boot/grub/grub.cfg
MKRESCUE = grub-mkrescue

all: $(NAME)

$(NAME): $(KERNEL) $(GRUB_CFG)
	cp $(KERNEL) $(ISO_DIR)/boot/
	$(MKRESCUE) --compress=xz -o $(NAME) $(ISO_DIR)

$(KERNEL): $(SRC) $(ASM_SRC)
	zig build # -Doptimize=ReleaseSafe

clean:
	rm -rf zig-out $(ISO_DIR)/boot/kfs.bin

fclean: clean
	rm -rf $(NAME)
	rm -rf .zig-cache

qemu: $(NAME)
	qemu-system-i386 -enable-kvm -cdrom $(NAME) -serial stdio

debug: $(NAME)
	qemu-system-i386 -cdrom $(NAME) -s -S &
	gdb $(KERNEL) -ex "target remote localhost:1234"

multimonitor: $(NAME)
	qemu-system-i386 -enable-kvm -device virtio-vga,max_outputs=2 -cdrom $(NAME) -serial stdio

.PHONY: all clean qemu multimonitor
