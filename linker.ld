ENTRY(_start)

VIRT =  0xC0000000;
PHYS =  0x00100000;

PHDRS
{
    bootdata    PT_LOAD FLAGS(0x6); /* RW */
    boottext    PT_LOAD FLAGS(0x5); /* RX */
    text        PT_LOAD FLAGS(0x5); /* RX */
    ro          PT_LOAD FLAGS(0x4); /* R */
    data        PT_LOAD FLAGS(0x6); /* RW */
    bss         PT_LOAD FLAGS(0x6); /* RW */
    debug       PT_LOAD FLAGS(0x4); /* R */
}

SECTIONS
{
    . = PHYS;

    .multiboot.data ALIGN(8) :
    {
        KEEP(*(.multiboot.data))
    }                           :bootdata

    .multiboot.text ALIGN(1) :
    {
        KEEP(*(.multiboot.text))
    }                           :boottext

    _kernel_start = .;
    . += VIRT;

    .text ALIGN(4K) :           AT(ADDR(.text) - VIRT)
    {
        *(.text .text.*)
    }                           :text

    .rodata ALIGN(4K) :         AT(ADDR(.rodata) - VIRT)
    {
        *(.rodata .rodata.*)
        *(.eh_frame_hdr)
        *(.eh_frame)
    }                           :ro

    .data ALIGN(4K) :           AT(ADDR(.data) - VIRT)
    {
        *(.data .data.*)
    }                           :data

    .bss ALIGN(4K) (NOLOAD) :   AT(ADDR(.bss) - VIRT)
    {
        *(COMMON)
        *(.bss .bss.*)
        *(.bootstrap_stack)
    }                           :bss
    
    _kernel_end = .;

    /DISCARD/ : {
        *(.debug_info)
        *(.debug_abbrev)
        *(.debug_aranges)
        *(.debug_line)
        *(.debug_loc)
        *(.debug_ranges)
        /* *(.debug_str) */
        *(.debug_pubnames)
        *(.debug_pubtypes)
        *(.comment)
    }
}
