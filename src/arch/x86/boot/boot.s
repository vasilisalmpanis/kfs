# Declare constants for the multiboot header.
.set ALIGN,    1<<0             # align loaded modules on page boundaries
.set MEMINFO,  1<<1             # provide memory map
.set VIDEO,    1<<2  
.set FLAGS,    ALIGN | MEMINFO | VIDEO # this is the Multiboot 'flag' field

# Video mode preferences
.set GRAPHICS_MODE,	1        	# 0 = linear text, 1 = graphics mode
.set WIDTH,			1920      	# desired width
.set HEIGHT,		1080      	# desired height
.set DEPTH,			32       	# desired bits per pixel

.set MAGIC,    0x1BADB002       # 'magic number' lets bootloader find the header
.set CHECKSUM, -(MAGIC + FLAGS) # checksum of above, to prove we are multiboot

# Declare a multiboot header that marks the program as a kernel.
.section .multiboot.data, "aw"
	.align 4
	.long MAGIC
	.long FLAGS
	.long CHECKSUM
	# Video mode fields
	.long 0                     # header_addr
	.long 0                     # load_addr
	.long 0                     # load_end_addr
	.long 0                     # bss_end_addr
	.long 0                     # entry_addr
	.long GRAPHICS_MODE         # indicates graphics mode
	.long WIDTH
	.long HEIGHT
	.long DEPTH

# Allocate the initial stack.
.section .bootstrap_stack, "aw", @nobits
stack_bottom:
.skip 16384 * 10# 16 KiB
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
    .rept 768-3
    .long 0                    # Fill remaining entries with 0s
    .endr

    .long (0 << 22) | 0b10000011   # Map page 0
    .long (1 << 22) | 0b10000011   # Map page 1
    .long (2 << 22) | 0b10000011   # Map page 2
    .long (3 << 22) | 0b10000011   # Map page 3 first 16 mb of physical memory mapped
    .rept 256-4
    .long 0                    # Fill remaining entries with 0s
    .endr
