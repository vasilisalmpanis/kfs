/* Declare constants for the multiboot header. */
.set ALIGN,    1<<0             /* align loaded modules on page boundaries */
.set MEMINFO,  1<<1             /* provide memory map */
.set VIDEO,	1<<2
.set FLAGS,    ALIGN | MEMINFO | VIDEO   /* this is the Multiboot 'flag' field */
.set MAGIC,    0x1BADB002       /* 'magic number' lets bootloader find the header */
.set CHECKSUM, -(MAGIC + FLAGS) /* checksum of above, to prove we are multiboot */

.section .multiboot
	.align 4
	.long MAGIC
	.long FLAGS
	.long CHECKSUM
	.long 0
	.long 0
	.long 0
	.long 0
	.long 0
	.long 1
	.long 800
	.long 600
	.long 32


.section .bss
	.align 16
stack_bottom:
	.skip 16384 * 40 # 16 KiB
stack_top:

.section .text
.global _start
.type _start, @function
_start:
	mov $stack_top, %esp
	xor %ebp, %ebp  /* 0 the ebp register to allow stack traces */
	push %ebx
	push %eax
	call kernel_main
	cli
1:	hlt
	jmp 1b

.size _start, . - _start
