BITS 32

userspace:
	;mov eax, 5
	;int 0x80
	;jmp userspace
fork:
	mov eax, 57
	int 0x80
	cmp eax, 0
	je child
parent:
	mov ebx, eax
	mov eax, 61
	int 0x80
	cmp eax, 5
	je res
	; jmp parent
new:
	jmp new
res:
	mov eax, 10
	int 0x80
	jmp new
child:
	mov eax, 0
incr:
	inc eax
	cmp eax, 10000000
	jne incr
	mov eax, 60
	mov ebx, 5
	int 0x80
	; jmp child
child_after:
	jmp child_after
