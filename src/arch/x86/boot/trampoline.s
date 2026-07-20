.section .text
.global smp_trampoline_start
.code16
smp_trampoline_start:
	cli
	cld
	mov %cs, %ax
	mov %ax, %ss
	mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs

	# Load GDT pointer (lgdt reads via ds, which we just set to cs)
	lgdt [gdt_ptr - smp_trampoline_start]

	# Enable protected mode (CR0.PE). Without this the far jump below is
	# just a real-mode far jump, not a segment-selector load.
	mov %cr0, %eax
	or $0x1, %eax
	mov %eax, %cr0

	# Enter 32-bit protected mode. Selector 0x8 = code segment.
	# Absolute physical target: the trampoline is copied to 0x8000.
	jmp $0x8, $0x8000 + smp32 - smp_trampoline_start

.section .text
.code32
smp32:
	mov $0x10, %ax
	mov %ax, %ds
	mov %ax, %es
	mov %ax, %ss
	mov %ax, %fs
	mov %ax, %gs

	movl $(initial_page_dir - 0xC0000000), %ecx
	movl %ecx, %cr3

	# Enable 4MB pages (CR4.PSE)
	mov %cr4, %ecx
	orl $0x10, %ecx
	mov %ecx, %cr4

	# Enable paging (CR0.PG)
	mov %cr0, %ecx
	orl $0x80000000, %ecx
	mov %ecx, %cr0

	# Load the absolute (higher-half) address of smp_higher_half and jump.
	# A relative jmp would be wrong: EIP is still at low physical 0x8000.
	mov $smp_higher_half, %eax
	jmp *%eax

.section .text
smp_higher_half:

	# ap_stack already holds the top of the stack.
	mov [ap_stack], %esp
	xor %ebp, %ebp

	call apMain

	cli
	hlt
1:
	jmp 1b

.section .text
gdt_start:
	.quad 0x0000000000000000
	.quad 0x00CF9A000000FFFF
	.quad 0x00CF92000000FFFF
.section .text
gdt_end:

.section .text
gdt_ptr:
	.word gdt_end - gdt_start - 1
	# Runtime physical location of the GDT (trampoline copied to 0x8000),
	# NOT the higher-half link address.
	.long 0x8000 + gdt_start - smp_trampoline_start

.section .text
.global smp_trampoline_end
smp_trampoline_end:
