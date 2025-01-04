NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin

ISO_DIR = iso

all: $(NAME)

$(NAME): $(KERNEL)
	cp $(KERNEL) $(ISO_DIR)/boot/
	grub-mkrescue -o $(NAME) $(ISO_DIR)

$(KERNEL):
	zig build

clean:
	rm -rf zig-out

qemu: $(NAME)
	qemu-system-i386 -enable-kvm -cdrom $(NAME) -serial stdio

.PHONY: all $(NAME) $(KERNEL) clean qemu
