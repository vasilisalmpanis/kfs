BITS 32

userspace:
    mov eax, 62
    mov ebx, 2
    mov ecx, 1
    int 0x80
    mov eax, 62
    mov ebx, 2
    mov ecx, 31
    int 0x80
holder:
    jmp userspace
