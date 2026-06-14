SECTIONS
{
    . = SIZEOF_HEADERS;

    .text : { *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text
    .data : { *(.data .data.*) } :text

    .gnu.version    : { *(.gnu.version) }    :text
    .gnu.version_d  : { *(.gnu.version_d) }  :text
    .gnu.version_r  : { *(.gnu.version_r) }  :text

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

VERSION
{
    LINUX_2.6 {
    global:
        __vdso_clock_gettime;
        __vdso_clock_gettime64;
    local: *;
    };
}
