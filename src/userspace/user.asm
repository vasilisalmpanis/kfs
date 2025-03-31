BITS 32

userspace:
    mov eax, 62
    mov ebx, 2
    mov ecx, 1
    int 0x80
    ; In this point the result of kill should be stored in eax
    cmp eax, 0
    jne userspace
holder:
    jmp holder
