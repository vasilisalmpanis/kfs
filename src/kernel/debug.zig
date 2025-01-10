const printf = @import("printf.zig").printf;


const stackframe = struct {
    ebp : ?*stackframe = null,
    eip : u32,

    pub fn init() stackframe {
        return stackframe{
            .ebp = null,
            .eip = 0,
        };
    }
};

/// Print the currect stack frames up to a maxFrame 
/// number specified as argument.
/// @param maxFrames: maximum amount of frames to trace.
pub fn TraceStackTrace(maxFrames : u32 ) void {
    var stk : ?*stackframe = 
     asm ("movl %ebp, %[result]"
        : [result] "={eax}" (-> *stackframe),
        : :
    );
    printf("Stack Trace:\n",.{});
    var frame : u32 = 0;
    while (frame < maxFrames and stk != null) : (frame += 1) {
        if (stk != null) {
            printf("  0x{x}     \n", .{ stk.?.eip });
        }
        stk = stk.?.ebp;
    }
    printRegisters();
}

const RegisterState = struct {
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
    esi: usize,
    edi: usize,
    ebp: usize,
    esp: usize,

    fn init() RegisterState {
        return RegisterState{.eax = 0,
                             .ebx = 0,
                             .ecx = 0,
                             .edx = 0,
                             .esi = 0,
                             .edi = 0,
                             .ebp = 0,
                             .esp = 0};
    }
};

pub fn printRegisters() void {
    var state: RegisterState = RegisterState.init();
    saveRegisters(&state);
    printf("Register Values:\n", .{});
    printf("EAX: 0x{X:0>8}\n", .{state.eax});
    printf("EBX: 0x{X:0>8}\n", .{state.ebx});
    printf("ECX: 0x{X:0>8}\n", .{state.ecx});
    printf("EDX: 0x{X:0>8}\n", .{state.edx});
    printf("ESI: 0x{X:0>8}\n", .{state.esi});
    printf("EDI: 0x{X:0>8}\n", .{state.edi});
    printf("EBP: 0x{X:0>8}\n", .{state.ebp});
    printf("ESP: 0x{X:0>8}\n", .{state.esp});
}

fn saveRegisters(state: *RegisterState) void {
    state.eax = asm volatile (
        \\ mov %%eax, %[value]
        : [value] "=r" (-> usize),
    );
    state.ebx = asm volatile (
        \\ mov %%ebx, %[value]
        : [value] "=r" (-> usize),
    );
    state.ecx = asm volatile (
        \\ mov %%ecx, %[value]
        : [value] "=r" (-> usize),
    );
    state.edx = asm volatile (
        \\ mov %%edx, %[value]
        : [value] "=r" (-> usize),
    );
    state.esi = asm volatile (
        \\ mov %%esi, %[value]
        : [value] "=r" (-> usize),
    );
    state.edi = asm volatile (
        \\ mov %%edi, %[value]
        : [value] "=r" (-> usize),
    );
    state.ebp = asm volatile (
        \\ mov %%ebp, %[value]
        : [value] "=r" (-> usize),
    );
    state.esp = asm volatile (
        \\ mov %%esp, %[value]
        : [value] "=r" (-> usize),
    );
}
