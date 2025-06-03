SECTIONS
{
  . = 0x1000;
  .text.main : AT (0x1000) {
    *(.text.main)
  }
  .text : {
    *(.text*)
  }

  .rodata : ALIGN(0x1000) {
    *(.rodata*)
  }

  .data : ALIGN(0x1000) {
    *(.data*)
  }

  .bss : ALIGN(0x1000) {
    *(.bss*)
  }
}
