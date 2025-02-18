const krn = @import("kernel");
pub const registers_t = packed struct {
    gs: u32, 
    fs: u32,
    es: u32,
    ds: u32,      // pushed the segs last 
    edi: u32, 
    esi: u32, 
    ebp: u32, 
    esp: u32, 
    ebx: u32, 
    edx: u32, 
    ecx: u32, 
    eax: i32,
    int_no: u32, 
    err_code: u32,
    eip: u32, 
    cs: u32, 
    eflags: u32, 
    useresp: u32, 
    ss: u32,
};

pub inline fn printRegisters(state: *registers_t) void {
    krn.logger.INFO("EIP: {X:0>8} ({X:0>8})\n", .{state.eip, 0});
    
    krn.logger.INFO("EAX: {X:0>8} EBX: {X:0>8} ECX: {X:0>8} EDX: {X:0>8}\n", 
        .{state.eax, state.ebx, state.ecx, state.edx});
    krn.logger.INFO("ESI: {X:0>8} EDI: {X:0>8} EBP: {X:0>8} ESP: {X:0>8}\n",
        .{state.esi, state.edi, state.ebp, state.esp});
    krn.logger.INFO("EFLAGS: {X:0>8}\n", .{state.eflags});
    krn.logger.INFO("gs {X:0>8}\n", .{state.gs});
    krn.logger.INFO("fs {X:0>8}\n", .{state.fs});
    krn.logger.INFO("es {X:0>8}\n", .{state.es});
    krn.logger.INFO("ds {X:0>8}\n", .{state.ds});
    krn.logger.INFO("cs {X:0>8}\n", .{state.cs});
    krn.logger.INFO("ss {X:0>8}\n", .{state.ss});
    
}
