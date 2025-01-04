NAME = kfs.iso
KERNEL = zig-out/bin/kfs.bin


all: $(NAME)

$(NAME): $(KERNEL)
	cp $(KERNEL) ./iso/boot/
	grub-mkrescue -o $(NAME) ./iso/

$(KERNEL):
	zig build

.PHONY: all $(NAME) $(KERNEL)

