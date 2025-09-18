ENTRY(_start)

SECTIONS
{
  . = 0x10000;  /* For some reason i686 toolchain was putting section at address 0*/

  .text : ALIGN(0x1000) {
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
