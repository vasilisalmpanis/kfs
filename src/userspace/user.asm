BITS 32

pid1:
	push ebp
	mov ebp, esp
	call fork
	cmp eax, 0
	je child1
infinite_wait:
	mov ebx, 0 ; FIX: there is a bug with wait4. If we put -1 as pid @intCast causes an exception. Investigate.
	call wait4
	jmp infinite_wait

child1:
	xor eax, eax
incr:
	inc eax
	cmp eax, 10000000
	jne incr
	call exit
catch:
	jmp catch

fork:
	push ebp
	mov ebp, esp
	mov eax, 57
	int 0x80
	pop ebp
	ret

wait4:
	push ebp
	mov ebp, esp
	mov eax, 61
	int 0x80
	pop ebp
	ret
exit:
	push ebp
	mov ebp, esp
	mov eax, 60
	int 0x80
	pop ebp
	ret
