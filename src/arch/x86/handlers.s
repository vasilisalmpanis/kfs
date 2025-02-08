.macro pushaq 
    push %eax
    push %ebx
    push %ecx
    push %edx
    push %esi
    push %edi
    push %ebp
    #push r8
    #push r9
    #push r10
    #push r11
    #push r12
    #push r13
    #push r14
    #push r15
.endm

.macro popaq
    #pop r15
    #pop r14
    #pop r13
    #pop r12
    #pop r11
    #pop r10
    #pop r9
    #pop r8
    pop %ebp
    pop %edi
    pop %esi
    pop %edx
    pop %ecx
    pop %ebx
    pop %eax
.endm

.macro isr_err_stub num
isr_stub_\num:
    cli
    push $\num       # Push interrupt number onto stack
    call exception_handler
    addl $4, %esp    # Clean up stack (pop interrupt number)
    addl $4, %esp    # Remove error code (only for error-code exceptions)
    iretl
.endm

.macro isr_no_err_stub num
isr_stub_\num:
    cli
    push $\num       # Push interrupt number onto stack
    call exception_handler
    addl $4, %esp    # Clean up stack (pop interrupt number)
    iretl
.endm

.extern exception_handler
isr_no_err_stub 0
isr_no_err_stub 1
isr_no_err_stub 2
isr_no_err_stub 3
isr_no_err_stub 4
isr_no_err_stub 5
isr_no_err_stub 6
isr_no_err_stub 7
isr_err_stub    8
isr_no_err_stub 9
isr_err_stub    10
isr_err_stub    11
isr_err_stub    12
isr_err_stub    13
isr_err_stub    14
isr_no_err_stub 15
isr_no_err_stub 16
isr_err_stub    17
isr_no_err_stub 18
isr_no_err_stub 19
isr_no_err_stub 20
isr_no_err_stub 21
isr_no_err_stub 22
isr_no_err_stub 23
isr_no_err_stub 24
isr_no_err_stub 25
isr_no_err_stub 26
isr_no_err_stub 27
isr_no_err_stub 28
isr_no_err_stub 29
isr_err_stub    30
isr_no_err_stub 31

.macro ISR_STUB_ENTRY num
    .long isr_stub_\num
.endm

.global isr_stub_table
.section .data
isr_stub_table:
    .long isr_stub_0
    .long isr_stub_1
    .long isr_stub_2
    .long isr_stub_3
    .long isr_stub_4
    .long isr_stub_5
    .long isr_stub_6
    .long isr_stub_7
    .long isr_stub_8
    .long isr_stub_9
    .long isr_stub_10
    .long isr_stub_11
    .long isr_stub_12
    .long isr_stub_13
    .long isr_stub_14
    .long isr_stub_15
    .long isr_stub_16
    .long isr_stub_17
    .long isr_stub_18
    .long isr_stub_19
    .long isr_stub_20
    .long isr_stub_21
    .long isr_stub_22
    .long isr_stub_23
    .long isr_stub_24
    .long isr_stub_25
    .long isr_stub_26
    .long isr_stub_27
    .long isr_stub_28
    .long isr_stub_29
    .long isr_stub_30
    .long isr_stub_31
