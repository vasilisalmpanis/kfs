BITS 32

userspace:
    mov eax, 62
    mov ebx, 3
    mov ecx, 1
    int 0x80
holder:
    jmp holder
