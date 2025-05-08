SECTIONS
{
  . = 0x1000;
  .text.main : AT (0x1000) {
    *(.text.main)
  }
  .text : {
    *(.text*)
  }

  .rodata : {
    *(.rodata*)
  }

  .data : {
    *(.data*)
  }

  .bss : {
    *(.bss*)
  }
}
