.code32
# Multiboot2 header constants
.set MULTIBOOT2_MAGIC,           0xe85250d6
.set MULTIBOOT2_ARCHITECTURE,    0          # i386 protected mode
.set MULTIBOOT2_HEADER_LENGTH,   (multiboot2_header_end - multiboot2_header_start)
.set MULTIBOOT2_CHECKSUM,        -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCHITECTURE + MULTIBOOT2_HEADER_LENGTH)

# Video mode preferences  
.set WIDTH,             0     # desired width
.set HEIGHT,            0     # desired height
.set DEPTH,             32       # desired bits per pixel

# Tag types
.set MULTIBOOT2_TAG_END,              0
.set MULTIBOOT2_TAG_INFORMATION,      1
.set MULTIBOOT2_TAG_FRAMEBUFFER,      5

# Tag flags
.set MULTIBOOT2_TAG_OPTIONAL,         1

# Declare a multiboot2 header that marks the program as a kernel
.section .multiboot.data, "aw"
    .align 8
multiboot2_header_start:
    # Multiboot2 header
    .long MULTIBOOT2_MAGIC
    .long MULTIBOOT2_ARCHITECTURE  
    .long MULTIBOOT2_HEADER_LENGTH
    .long MULTIBOOT2_CHECKSUM
    
    # Information request tag (equivalent to MEMINFO flag)
    .align 8
information_tag_start:
    .word MULTIBOOT2_TAG_INFORMATION    # type
    .word 0                             # flags (required)
    .long (information_tag_end - information_tag_start)  # size
    .long 4                             # memory map request
    .long 6                             # memory info request
information_tag_end:
    
    # Framebuffer tag (equivalent to VIDEO flag and mode settings)
    .align 8
framebuffer_tag_start:
    .word MULTIBOOT2_TAG_FRAMEBUFFER    # type
    .word MULTIBOOT2_TAG_OPTIONAL       # flags (optional)
    .long (framebuffer_tag_end - framebuffer_tag_start)  # size
    .long WIDTH                         # width
    .long HEIGHT                        # height
    .long DEPTH                         # depth (bits per pixel)
framebuffer_tag_end:
    
    # End tag
    .align 8
    .word MULTIBOOT2_TAG_END            # type
    .word 0                             # flags
    .long 8                             # size
    
multiboot2_header_end:

# Allocate the initial stack.
.section .bootstrap_stack, "aw", @nobits
.align 16
.globl stack_bottom
stack_bottom:
.skip 4096 * 1024
.globl stack_top
stack_top:

# Preallocate pages used for paging. Don't hard-code addresses and assume they
# are available, as the bootloader might have loaded its multiboot structures or
# modules there. This lets the bootloader know it must avoid the addresses.
.section .bss, "aw", @nobits
	.align 4096
boot_page_directory:
	.skip 4096
boot_page_table1:
	.skip 4096
# Further page tables may be required if the kernel grows beyond 3 MiB.

# The kernel entry point.
.section .multiboot.text, "a"

.global _start
.type _start, @function
_start:
	# Physical address of boot_page_table1.
	# TODO: I recall seeing some assembly that used a macro to do the
	#       conversions to and from physical. Maybe this should be done in this
	#       code as well?
	movl $(initial_page_dir - 0xC0000000), %ecx
	movl %ecx, %cr3

	mov %cr4, %ecx
	orl $0x10, %ecx
	mov %ecx, %cr4

	mov %cr0, %ecx
	orl $0x80000000, %ecx
	mov %ecx, %cr0

	jmp higher_half

.section .text
higher_half:

	# Set up the stack.
	mov $stack_top, %esp
	xor %ebp, %ebp

	# call print
	# Enter the high-level kernel.
	push %ebx
	push %eax
	call kernel_main

	# Infinite loop if the system has nothing more to do.
	cli
1:	hlt
	jmp 1b

.section .data
.align 4096

.global initial_page_dir
initial_page_dir:
    .long 0b10000011           # First entry in the page directory
    .long 0b10000011           # First entry in the page directory
    .long 0b10000011           # First entry in the page directory
    .long 0b10000011           # First entry in the page directory
    .rept 768-4
    .long 0                    # Fill remaining entries with 0s
    .endr

    .long (0 << 22) | 0b10000011   # Map page 0
    .long (1 << 22) | 0b10000011   # Map page 0
    .long (2 << 22) | 0b10000011   # Map page 0
    .long (3 << 22) | 0b10000011   # Map page 0
    .rept 256-4
    .long 0                    # Fill remaining entries with 0s
    .endr
