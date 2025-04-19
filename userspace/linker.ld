SECTIONS
{
  . = 0x1000;
  .text.main : {
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
