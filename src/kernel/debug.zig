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
    // General Purpose Registers
    eax: usize,
    ebx: usize,
    ecx: usize,
    edx: usize,
    esi: usize,
    edi: usize,
    ebp: usize,
    esp: usize,
    // Segment Registers
    cs: u16,
    ds: u16,
    es: u16,
    fs: u16,
    gs: u16,
    ss: u16,

    pub fn init() RegisterState {
        return .{
            .eax = 0, .ebx = 0, .ecx = 0, .edx = 0,
            .esi = 0, .edi = 0, .ebp = 0, .esp = 0,
            .cs = 0, .ds = 0, .es = 0, .fs = 0, .gs = 0, .ss = 0,
        };
    }
};

pub fn printRegisters() void {
    var state: RegisterState = RegisterState.init();
    asm volatile ("xor %eax, %eax":::);
    saveRegisters(&state);
    printf("\nCPU: {d} PID: {d}\n", .{0, 0});
    printf("EIP: {X:0>8} ({X:0>8})\n", .{0, 0});
    
    // General purpose registers
    printf("EAX: {X:0>8} EBX: {X:0>8} ECX: {X:0>8} EDX: {X:0>8}\n", 
        .{state.eax, state.ebx, state.ecx, state.edx});
    printf("ESI: {X:0>8} EDI: {X:0>8} EBP: {X:0>8} ESP: {X:0>8}\n",
        .{state.esi, state.edi, state.ebp, state.esp});
    
    // Segment registers
    printf("CS: {X:0>4} DS: {X:0>4} ES: {X:0>4} FS: {X:0>4} GS: {X:0>4} SS: {X:0>4}\n",
        .{state.cs, state.ds, state.es, state.fs, state.gs, state.ss});
}

fn saveRegisters(state: *RegisterState) void {
    // General Purpose Registers
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
    // Segment Registers
    state.cs = asm volatile (
        \\ mov %%cs, %[value]
        : [value] "=r" (-> u16),
    );
    state.ds = asm volatile (
        \\ mov %%ds, %[value]
        : [value] "=r" (-> u16),
    );
    state.es = asm volatile (
        \\ mov %%es, %[value]
        : [value] "=r" (-> u16),
    );
    state.fs = asm volatile (
        \\ mov %%fs, %[value]
        : [value] "=r" (-> u16),
    );
    state.gs = asm volatile (
        \\ mov %%gs, %[value]
        : [value] "=r" (-> u16),
    );
    state.ss = asm volatile (
        \\ mov %%ss, %[value]
        : [value] "=r" (-> u16),
    );
}
