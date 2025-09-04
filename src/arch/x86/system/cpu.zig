const krn = @import("kernel");
const KERNEL_CODE_SEGMENT = @import("../idt.zig").KERNEL_CODE_SEGMENT;
const KERNEL_DATA_SEGMENT = @import("../idt.zig").KERNEL_DATA_SEGMENT;
const USER_CODE_SEGMENT = @import("../idt.zig").USER_CODE_SEGMENT;
const USER_DATA_SEGMENT = @import("../idt.zig").USER_DATA_SEGMENT;


pub const Regs = struct {
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

    pub fn init() Regs {
        return Regs{
            .gs = KERNEL_DATA_SEGMENT,
            .fs = KERNEL_DATA_SEGMENT,
            .es = KERNEL_DATA_SEGMENT,
            .ds = KERNEL_DATA_SEGMENT,
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
            .cs = KERNEL_CODE_SEGMENT,
            .eflags = 0,
            .useresp = 0,
            .ss = 0,
        };
    }

    pub fn dump(self: *Regs) void {
        krn.logger.INFO("EIP: {X:0>8}\n", .{ self.eip});

        krn.logger.INFO("EAX: {X:0>8} EBX: {X:0>8} ECX: {X:0>8} EDX: {X:0>8}\n", .{ self.eax, self.ebx, self.ecx, self.edx });
        krn.logger.INFO("ESI: {X:0>8} EDI: {X:0>8} EBP: {X:0>8} ESP: {X:0>8}\n", .{ self.esi, self.edi, self.ebp, self.esp });
        krn.logger.INFO("EFLAGS: {X:0>8}\n", .{self.eflags});
        krn.logger.INFO("USERESP: {X:0>8}\n", .{self.useresp});
        krn.logger.INFO("gs {X:0>8}\n", .{self.gs});
        krn.logger.INFO("fs {X:0>8}\n", .{self.fs});
        krn.logger.INFO("es {X:0>8}\n", .{self.es});
        krn.logger.INFO("ds {X:0>8}\n", .{self.ds});
        krn.logger.INFO("cs {X:0>8}\n", .{self.cs});
        krn.logger.INFO("ss {X:0>8}\n", .{self.ss});
    }

    pub fn isRing3(self: *Regs) bool {
        if (self.cs == KERNEL_CODE_SEGMENT)
            return false;
        return true;
    }
};

pub fn setupStack(
    stack_top: u32,
    eip: u32,
    useresp: u32,
    cs: u32,
    ss: u32
) u32 {
    var stack_ptr: [*]u32 = @ptrFromInt(stack_top - @sizeOf(Regs));
    stack_ptr[0] = ss;
    stack_ptr[1] = ss;
    stack_ptr[2] = ss;
    stack_ptr[3] = ss;              // segments
    stack_ptr[4] = 0;               // GPR
    stack_ptr[5] = 0;
    stack_ptr[6] = 0;
    stack_ptr[7] = 0;
    stack_ptr[8] = 0;
    stack_ptr[9] = 0;               // edx
    stack_ptr[10] = 0;              // ecx
    stack_ptr[11] = 0;              // eax
    stack_ptr[12] = 0;              // int code
    stack_ptr[13] = 0;              // error code
    stack_ptr[14] = eip;            // eip
    stack_ptr[15] = cs;             // cs
    stack_ptr[16] = 0x202;          // eflags
    stack_ptr[17] = useresp;        // useresp
    stack_ptr[18] = ss;             // ss
    return @intFromPtr(stack_ptr);
}

pub inline fn getEflags() u32 {
    return asm volatile (
        \\ pushf
        \\ pop %%eax
        \\ mov %eax, %[value]
        : [value] "={eax}" (-> u32),
    );
}

pub inline fn getESP() u32 {
    return asm volatile (
        \\ mov %esp, %[value]
        : [value] "={eax}" (-> u32),
    );
}
pub fn areIntEnabled() bool {
    const eflags = getEflags();
    if (eflags & (1<<9) == (1<<9))
        return true;
    return false;
}

pub inline fn archReschedule() void {
    asm volatile(
        \\ pushf
        \\ pop %%eax            # Pop into EAX
        \\ test $0x200, %%eax   # Test bit 9 (IF)
        \\ jz return_point      # Jump if interrupts are disabled
        \\ pushf
        \\ cli
        \\ push %[code_seg]     # CS (kernel code segment)
        \\ push $return_point
        \\ push $0
        \\ push $16
        \\ pusha
        \\ push %%ds
        \\ push %%es
        \\ push %%fs
        \\ push %%gs
        \\ mov %[data_seg], %%ax
        \\ mov %%ax, %%ds
        \\ mov %%ax, %%es
        \\ mov %%ax, %%fs
        \\ mov %%ax, %%gs
        \\ mov %%esp, %%eax
        \\ push %%eax
        \\ lea schedule, %%eax
        \\ call *%%eax
        \\ add $4, %%esp
        \\ mov %%eax, %%esp
        \\ pop %%gs
        \\ pop %%fs
        \\ pop %%es
        \\ pop %%ds
        \\ popa
        \\ add $8, %%esp
        \\ iret
        \\ return_point:
        \\ nop
        \\
        :
        : [code_seg] "i" (KERNEL_CODE_SEGMENT),
          [data_seg] "i" (KERNEL_DATA_SEGMENT)
        : .{ .memory = true }
    );
}

pub const TSS = packed struct {
    back_link: u16,
    _padding0: u16,
    esp0: u32,
    ss0: u16,
    _padding1: u16,
    esp1: u32,
    ss1: u16,
    _padding2: u16,
    esp2: u32,
    ss2: u16,
    _padding3: u16,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u16,
    cs: u16,
    ss: u16,
    ds: u16,
    fs: u16,
    gs: u16,
    ldt: u16,
    trace: u16,
    bitmap: u16,

    pub fn init() TSS {
        return TSS {
            .back_link = 0,
            .esp0 = 0,
            .ss0 = 0,
            .esp1 = 0,
            .ss1 = 0,
            .esp2 = 0,
            .ss2 = 0,
            .cr3= 0 ,
            .eip= 0 ,
            .eflags = 0,
            .eax = 0,
            .ecx = 0,
            .edx = 0,
            .ebx = 0,
            .esp = 0,
            .ebp = 0,
            .esi = 0,
            .edi = 0,
            .es = 0,
            .cs = 0,
            .ss = 0,
            .ds = 0,
            .fs = 0,
            .gs = 0,
            .ldt = 0,
            .trace = 0,
            .bitmap = 0,
            ._padding0 = 0,
            ._padding1 = 0,
            ._padding2 = 0,
            ._padding3 = 0,
        };
    }
};
