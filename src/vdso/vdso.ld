SECTIONS
{
    . = SIZEOF_HEADERS;

    .text : { *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text
    .data : { *(.data .data.*) } :text
    .dynamic : { *(.dynamic) } :text :dynamic

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.note.*)
        *(.bss)
        *(.bss.*)
        *(.got)
        *(.got.plt)
    }
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    dynamic PT_DYNAMIC FLAGS(4);
}
