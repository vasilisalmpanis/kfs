const krn = @import("kernel");
pub const registers_t = struct {
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

    pub fn init() registers_t {
        return registers_t{
            .gs = 0x10,
            .fs = 0x10,
            .es = 0x10,
            .ds = 0x10,
            .edi = 0,
            .esi = 0,
            .ebp = 0,
            .esp = 0,
            .ebx = 0,
            .edx = 0,
            .ecx = 0,
            .eax = 0,
            .int_no = 0,
            .err_code = 0,
            .eip = 0,
            .cs = 0x8,
            .eflags = 0,
            .useresp = 0,
            .ss = 0,
        };
    }

    pub fn dump(self: *registers_t) void {
        krn.logger.INFO("EIP: {X:0>8}\n", .{ self.eip});

        krn.logger.INFO("EAX: {X:0>8} EBX: {X:0>8} ECX: {X:0>8} EDX: {X:0>8}\n", .{ self.eax, self.ebx, self.ecx, self.edx });
        krn.logger.INFO("ESI: {X:0>8} EDI: {X:0>8} EBP: {X:0>8} ESP: {X:0>8}\n", .{ self.esi, self.edi, self.ebp, self.esp });
        krn.logger.INFO("EFLAGS: {X:0>8}\n", .{self.eflags});
        krn.logger.INFO("gs {X:0>8}\n", .{self.gs});
        krn.logger.INFO("fs {X:0>8}\n", .{self.fs});
        krn.logger.INFO("es {X:0>8}\n", .{self.es});
        krn.logger.INFO("ds {X:0>8}\n", .{self.ds});
        krn.logger.INFO("cs {X:0>8}\n", .{self.cs});
        krn.logger.INFO("ss {X:0>8}\n", .{self.ss});
    }
};
