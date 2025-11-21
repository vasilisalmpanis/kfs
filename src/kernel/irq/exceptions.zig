const Regs = @import("arch").Regs;
const std = @import("std");
const dbg = @import("debug");
const registerExceptionHandler = @import("./manage.zig").registerExceptionHandler;
const kernel = @import("../main.zig");

pub const Exceptions = enum {
    DivisionError,
    Debug,
    NonMaskableInterrupt,
    Breakpoint,
    Overflow,
    BoundRangeExceeded,
    InvalidOpcode,
    DeviceNotAvailable,
    DoubleFault,
    CoprocessorSegmentOverrun,
    InvalidTSS,
    SegmentNotPresent,
    StackSegmentFault,
    GeneralProtectionFault,
    PageFault,
    Reserved_1,
    x87FloatingPointException,
    AlignmentCheck,
    MachineCheck,
    SIMDFloatingPointException,
    VirtualizationException,
    ControlProtectionException,
    Reserved_2,
    Reserved_3,
    Reserved_4,
    Reserved_5,
    Reserved_6,
    Reserved_7,
    HypervisorInjectionException,
    VMMCommunicationException,
    SecurityException,
    Reserved_8,
    // TripleFault,
    // FPUErrorInterrupt,
};

fn hDivisionError(regs: *Regs) void {
    _ = regs;
    @panic("Division by zero");
}

fn hDebug(regs: *Regs) void {
    _ = regs;
    @panic("Debug");
}

pub fn hNonMaskableInterrupt(regs: *Regs) void {
    _ = regs;
    @panic("hNonMaskableInterrupt");
}

pub fn hBreakpoint(regs: *Regs) void {
    _ = regs;
}

pub fn hOverflow(regs: *Regs) void {
    _ = regs;
}

pub fn hBoundRangeExceeded(regs: *Regs) void {
    _ = regs;
    @panic("hBoundRangeExceeded");
}

pub fn hInvalidOpcode(regs: *Regs) void {
    regs.dump();
    @panic("hInvalidOpcode");
}

pub fn hDeviceNotAvailable(regs: *Regs) void {
    _ = regs;
    @panic("hDeviceNotAvailable");
}

pub fn hDoubleFault(regs: *Regs) void {
    _ = regs;
    @panic("hDoubleFault");
}

pub fn hCoprocessorSegmentOverrun(regs: *Regs) void {
    _ = regs;
    @panic("hCoprocessorSegmentOverrun");
}

pub fn hInvalidTSS(regs: *Regs) void {
    _ = regs;
    @panic("hInvalidTSS");
}

pub fn hSegmentNotPresent(regs: *Regs) void {
    _ = regs;
    @panic("hSegmentNotPresent");
}

pub fn hStackSegmentFault(regs: *Regs) void {
    _ = regs;
    @panic("hStackSegmentFault");
}

pub fn hGeneralProtectionFault(regs: *Regs) void {
    kernel.logger.ERROR("PID {d}\n", .{kernel.task.current.pid});
    regs.dump();
    dbg.traceStackTrace(20);
    @panic("hGeneralProtectionFault");
}

pub fn hPageFault(regs: *Regs) void {
    var addr: u32 = 0;
    addr = asm volatile("mov %%cr2, %[val]" : [val] "={eax}" (-> u32));
    asm volatile ("cli");
    kernel.logger.DEBUG("PID {d}\n", .{kernel.task.current.pid});
    kernel.logger.DEBUG(
        \\Page Fault at addr: {x}
        \\EIP: {x}
        \\  present:      {d}
        \\  write:        {d}
        \\  user:         {d}
        \\  reserved:     {d}
        \\  intsr. fetch: {d}
        , .{
            addr,
            regs.eip,
            regs.err_code & 0x1,
            regs.err_code & 0x2,
            regs.err_code & 0x4,
            regs.err_code & 0x8,
            regs.err_code & 0x10,
        });
    dbg.traceStackTrace(20);
    while (true) {}
    regs.dump();
    @panic("hPageFault");
}

pub fn hReserved_1(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_1");
}

pub fn hx87FloatingPointException(regs: *Regs) void {
    _ = regs;
    @panic("hx87FloatingPointException");
}

pub fn hAlignmentCheck(regs: *Regs) void {
    _ = regs;
    @panic("hAlignmentCheck");
}

pub fn hMachineCheck(regs: *Regs) void {
    _ = regs;
    @panic("hMachineCheck");
}

pub fn hSIMDFloatingPointException(regs: *Regs) void {
    _ = regs;
    @panic("hSIMDFloatingPointException");
}

pub fn hVirtualizationException(regs: *Regs) void {
    _ = regs;
    @panic("hVirtualizationException");
}

pub fn hControlProtectionException(regs: *Regs) void {
    _ = regs;
    @panic("hControlProtectionException");
}

pub fn hReserved_2(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_2");
}

pub fn hReserved_3(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_3");
}

pub fn hReserved_4(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_4");
}

pub fn hReserved_5(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_5");
}

pub fn hReserved_6(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_6");
}

pub fn hReserved_7(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_7");
}

pub fn hHypervisorInjectionException(regs: *Regs) void {
    _ = regs;
    @panic("hHypervisorInjectionException");
}

pub fn hVMMCommunicationException(regs: *Regs) void {
    _ = regs;
    @panic("hVMMCommunicationException");
}

pub fn hSecurityException(regs: *Regs) void {
    _ = regs;
    @panic("hSecurityException");
}

pub fn hReserved_8(regs: *Regs) void {
    _ = regs;
    @panic("hReserved_8");
}

const ExceptionHandlers = std.EnumMap(
    Exceptions,
    *const fn (regs: *Regs) void
).init(.{
    .DivisionError                  = &hDivisionError,
    .Debug                          = &hDebug,
    .NonMaskableInterrupt           = &hNonMaskableInterrupt,
    .Breakpoint                     = &hBreakpoint,
    .Overflow                       = &hOverflow,
    .BoundRangeExceeded             = &hBoundRangeExceeded,
    .InvalidOpcode                  = &hInvalidOpcode,
    .DeviceNotAvailable             = &hDeviceNotAvailable,
    .DoubleFault                    = &hDoubleFault,
    .CoprocessorSegmentOverrun      = &hCoprocessorSegmentOverrun,
    .InvalidTSS                     = &hInvalidTSS,
    .SegmentNotPresent              = &hSegmentNotPresent,
    .StackSegmentFault              = &hStackSegmentFault,
    .GeneralProtectionFault         = &hGeneralProtectionFault,
    .PageFault                      = &hPageFault,
    .Reserved_1                     = &hReserved_1,
    .x87FloatingPointException      = &hx87FloatingPointException,
    .AlignmentCheck                 = &hAlignmentCheck,
    .MachineCheck                   = &hMachineCheck,
    .SIMDFloatingPointException     = &hSIMDFloatingPointException,
    .VirtualizationException        = &hVirtualizationException,
    .ControlProtectionException     = &hControlProtectionException,
    .Reserved_2                     = &hReserved_2,
    .Reserved_3                     = &hReserved_3,
    .Reserved_4                     = &hReserved_4,
    .Reserved_5                     = &hReserved_5,
    .Reserved_6                     = &hReserved_6,
    .Reserved_7                     = &hReserved_7,
    .HypervisorInjectionException   = &hHypervisorInjectionException,
    .VMMCommunicationException      = &hVMMCommunicationException,
    .SecurityException              = &hSecurityException,
    .Reserved_8                     = &hReserved_8,
});

pub fn registerExceptionHandlers() void {
    for (0..ExceptionHandlers.count()) |idx| {
        registerExceptionHandler(
            idx,
            @ptrCast(ExceptionHandlers.get(@enumFromInt(idx)))
        );
    }
}
