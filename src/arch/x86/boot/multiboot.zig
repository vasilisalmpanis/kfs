pub const multiboot_info = packed struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms_0: u32,
    syms_1: u32,
    syms_2: u32,
    syms_3: u32,
    mmap_length: u32,
    mmap_addr: u32,
};

pub const multiboot_memory_map = struct {
    size: u32,
    addr: [2]u32,
    len: [2]u32,
    type: u32,
};

pub export fn _start() noreturn {
    asm volatile(\\
        \\ /* Declare constants for the multiboot header. */
        \\ .set ALIGN,    1<<0             /* align loaded modules on page boundaries */
        \\ .set MEMINFO,  1<<1             /* provide memory map */
        \\ .set FLAGS,    ALIGN | MEMINFO  /* this is the Multiboot 'flag' field */
        \\ .set MAGIC,    0x1BADB002       /* 'magic number' lets bootloader find the header */
        \\ .set CHECKSUM, -(MAGIC + FLAGS) /* checksum of above, to prove we are multiboot */
        \\ 
        \\ .section .multiboot
        \\ 	.align 4
        \\ 	.long MAGIC
        \\ 	.long FLAGS
        \\ 	.long CHECKSUM
        \\ 
        \\ .section .bss
        \\ 	.align 16
        \\ stack_bottom:
        \\ 	.skip 524288
        \\ stack_top:
        \\ 
        \\ .section .text
        \\
        \\ 	mov $stack_top, %esp
        \\ 	xor %ebp, %ebp  /* 0 the ebp register to allow stack traces */
        \\ 	push %ebx
        \\ 	push %eax
        \\ 	call kernel_main
        \\ 
        \\ 	cli
        \\ 1: hlt
        \\ 	jmp 1b
        \\ 
        \\ .size _start, . - _start
    );
    while (true) {}
}
