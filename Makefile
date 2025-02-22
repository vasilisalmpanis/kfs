NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso
SRC_DIR = src

SRC = $(shell find $(SRC_DIR) -name '*.zig')
ASM_SRC = $(shell find $(SRC_DIR) -name '*.s')
GRUB_CFG = $(ISO_DIR)/boot/grub/grub.cfg

all: $(NAME)

$(NAME): $(KERNEL) $(GRUB_CFG)
	cp $(KERNEL) $(ISO_DIR)/boot/
	grub-mkrescue --compress=xz -o $(NAME) $(ISO_DIR)

$(KERNEL): $(SRC) $(ASM_SRC)
	zig build # -Doptimize=ReleaseSafe

clean:
	rm -rf zig-out

qemu: $(NAME)
	qemu-system-i386 -enable-kvm -cdrom $(NAME) -serial stdio

multimonitor: $(NAME)
	qemu-system-i386 -enable-kvm -device virtio-vga,max_outputs=2 -cdrom $(NAME) -serial stdio

.PHONY: all clean qemu multimonitor
