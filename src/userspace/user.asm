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
	mov eax, 10
	int 0x80
new:
	jmp new
child:
	mov eax, 11
	int 0x80
child_after:
	jmp child_after
