ENTRY (_start)

VMA = 0x10000000;

SECTIONS
{
    . = 0x00100000;
	/* The kernel will live at 3GB + 1MB in the virtual address space, */
	/* which will be mapped to 1MB in the physical address space. */
	/* Note that we page-align the sections. */

	.multiboot.data : {
		KEEP(*(.multiboot.data))
	}

	.multiboot.text : {
		KEEP(*(.multiboot.text))
	}

	_kernel_start = .;
	. += VMA;
	/* Add a symbol that indicates the start address of the kernel. */
	.text ALIGN (4K) : AT (ADDR (.text) - VMA)
	{
		*(.text)
	}
	.rodata ALIGN (4K) : AT (ADDR (.rodata) - VMA)
	{
		*(.rodata)
		*(.rodata.*)
		*(.rodata..*)
	}
	.data ALIGN (4K) : AT (ADDR (.data) - VMA)
	{
		*(.data)
		*(.data.*)
	}
	.bss ALIGN (4K) : AT (ADDR (.bss) - VMA)
	{
		*(COMMON)
		*(.bss)
		*(.bootstrap_stack)
	}
	/* Add a symbol that indicates the end address of the kernel. */
	_kernel_end = .;
}
