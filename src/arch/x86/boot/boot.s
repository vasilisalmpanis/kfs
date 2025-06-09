# Declare constants for the multiboot header.
.set ALIGN,    1<<0             # align loaded modules on page boundaries
.set MEMINFO,  1<<1             # provide memory map
.set VIDEO,    1<<2  
.set FLAGS,    ALIGN | MEMINFO | VIDEO # this is the Multiboot 'flag' field

# Video mode preferences
.set GRAPHICS_MODE,	1        	# 0 = linear text, 1 = graphics mode
.set WIDTH,			0      	# desired width
.set HEIGHT,			0      	# desired height
.set DEPTH,			32       	# desired bits per pixel

.set MAGIC,    0xE85250D6       # 'magic number' lets bootloader find the header
.set LEN,	header_end - multiboot_header
.set CHECKSUM, -(MAGIC + LEN) # checksum of above, to prove we are multiboot

# Declare a multiboot header that marks the program as a kernel.
.section .multiboot.data, "aw"
multiboot_header:
	.align 8
	.long MAGIC
	.long 0
	.long LEN
	.long CHECKSUM
	# Video mode fields
	# --- Framebuffer Tag ---
    	.short 5                # tag type (framebuffer)
    	.short 0                # reserved
    	.long 20                # size of tag
    	.long WIDTH             # width
    	.long HEIGHT            # height
    	.long DEPTH             # depth (bpp)

    	# --- End Tag ---
    	.align 8
    	.short 0                # tag type = 0 (end)
    	.short 0                # reserved
    	.long 8                 # size
header_end:

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
    .rept 768-2
    .long 0                    # Fill remaining entries with 0s
    .endr

    .long (0 << 22) | 0b10000011   # Map page 0
    .long (1 << 22) | 0b10000011   # Map page 0
    .rept 256-2
    .long 0                    # Fill remaining entries with 0s
    .endr
