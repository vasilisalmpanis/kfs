ENTRY (_start)

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
	. += 0xC0000000;

	/* Add a symbol that indicates the start address of the kernel. */
	.init_call ALIGN (4K) : AT (ADDR (.init_call) - 0xC0000000)
	{
		__init_call_start = .;

		/* Early init subsection */
		__init_call_early_start = .;
		KEEP(*(.init_call.early))
		__init_call_early_end = .;
		/* Regular init calls */

		KEEP(*(.init_call))

		/* Device init subsection */
		__init_call_device_start = .;
		KEEP(*(.init_call.device))
		__init_call_device_end = .;

		/* Overall section end */
		__init_call_end = .;
	}
	.text ALIGN (4K) : AT (ADDR (.text) - 0xC0000000)
	{
		*(.text)
	}
	.rodata ALIGN (4K) : AT (ADDR (.rodata) - 0xC0000000)
	{
		*(.rodata)
		*(.rodata.*)
		*(.rodata..*)
	}
	.data ALIGN (4K) : AT (ADDR (.data) - 0xC0000000)
	{
		*(.data)
		*(.data.*)
	}
	.bss ALIGN (4K) : AT (ADDR (.bss) - 0xC0000000)
	{
		*(COMMON)
		*(.bss)
		*(.bootstrap_stack)
	}
	/* Add a symbol that indicates the end address of the kernel. */
	_kernel_end = .;
}
