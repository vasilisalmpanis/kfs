const printf = @import("./printf.zig").printf;


const StackFrame = struct {
    ebp : ?*StackFrame = null,
    eip : u32,

    pub fn init() StackFrame {
        return StackFrame{
            .ebp = null,
            .eip = 0,
        };
    }
};

/// Print the currect stack frames up to a maxFrame 
/// number specified as argument. Save the current
/// register stake and print it.
/// @param maxFrames: maximum amount of frames to trace.
pub inline fn traceStackTrace(maxFrames : u32 ) void {
    var state: RegisterState = RegisterState.init();

    // save the state
    saveRegisters(&state);
    var stk : ?*StackFrame = 
     asm ("movl %ebp, %[result]"
        : [result] "={eax}" (-> *StackFrame),
        : :
    );
    printf("Stack Trace:\n",.{});
    var frame : u32 = 0;
    // unwind the stack
    while (frame < maxFrames and stk != null) : (frame += 1) {
        if (stk != null) {
            printf("  0x{x}     \n", .{ stk.?.eip });
        }
        stk = stk.?.ebp;
    }

    // dump the registers
    printRegisters(&state);
}

const RegisterState = struct {
    // General Purpose Registers
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
    esi: usize,
    edi: usize,
    ebp: usize,
    esp: usize,

    eflags: usize,

    pub fn init() RegisterState {
        return .{
            .eax = 0, .ebx = 0, .ecx = 0, .edx = 0,
            .esi = 0, .edi = 0, .ebp = 0, .esp = 0,
            .eflags = 0,
        };
    }
};

pub inline fn printRegisters(state: *RegisterState) void {
    printf("EIP: {X:0>8} ({X:0>8})\n", .{0, 0});
    
    // General purpose registers
    printf("EAX: {X:0>8} EBX: {X:0>8} ECX: {X:0>8} EDX: {X:0>8}\n", 
        .{state.eax, state.ebx, state.ecx, state.edx});
    printf("ESI: {X:0>8} EDI: {X:0>8} EBP: {X:0>8} ESP: {X:0>8}\n",
        .{state.esi, state.edi, state.ebp, state.esp});
    printf("EFLAGS: {X:0>8}\n", .{state.eflags});
    
}

inline fn saveRegisters(state: *RegisterState) void {
    // asm volatile ("movl $1, %eax");
    var value: usize = 0;

    // General Purpose Registers
    value = asm volatile (
        \\ # Read EAX
        : [out] "={eax}" (-> usize)
    );
    state.eax = value;

    // we use eax to pop eflags
    // from the stack
    value = asm volatile (
        \\ pushfd
        \\ pop %[out]
        : [out] "={eax}" (-> usize)
        ::
    );
    state.eflags = value;

    value = asm volatile (
        \\ # Read EBX
        : [out] "={ebx}" (-> usize)
    );
    state.ebx = value;
    value = asm volatile (
        \\ # Read ECX
        : [out] "={ecx}" (-> usize)
    );
    state.ecx = value;
    value = asm volatile (
        \\ # Read EDX
        : [out] "={edx}" (-> usize)
    );
    state.edx = value;
    value = asm volatile (
        \\ # Read ESI
        : [out] "={esi}" (-> usize)
    );
    state.esi = value;
    value = asm volatile (
        \\ # Read EDI
        : [out] "={edi}" (-> usize)
    );
    state.edi = value;
    value = asm volatile (
        \\ # Read EBP
        : [out] "={ebp}" (-> usize)
    );
    state.ebp = value;
    value = asm volatile (
        \\ # Read ESP
        : [out] "={esp}" (-> usize)
    );
    state.esp = value;

}
