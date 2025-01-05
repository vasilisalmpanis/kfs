.section .text
.global load_gdt
.type load_gdt, @function

load_gdt:
    lgdt (%edi)
    ret
