const Regs = @import("arch").Regs;
const std = @import("std");
const dbg = @import("debug");
const registerExceptionHandler = @import("./manage.zig").registerExceptionHandler;
const kernel = @import("../main.zig");
const arch = @import("arch");
const Signal = kernel.signals.Signal;

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

fn hDivisionError(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGFPE)
        ) catch {};
        return regs;
    }
    if (true) @panic("Division by zero");
}

fn hDebug(regs: *Regs) *Regs {
    return regs;
}

pub fn hNonMaskableInterrupt(regs: *Regs) *Regs {
    if (true) @panic("hNonMaskableInterrupt");
    return regs;
}

pub fn hBreakpoint(regs: *Regs) *Regs {
    return regs;
}

pub fn hOverflow(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    return regs;
}

pub fn hBoundRangeExceeded(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    if (true) @panic("hBoundRangeExceeded");
    return regs;
}

pub fn hInvalidOpcode(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGILL)
        ) catch {};
        return regs;
    }
    regs.dump();
    if (true) @panic("hInvalidOpcode");
    return regs;
}

pub fn hDeviceNotAvailable(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    if (true) @panic("hDeviceNotAvailable");
    return regs;
}

pub fn hDoubleFault(regs: *Regs) *Regs {
    if (true) @panic("hDoubleFault");
    return regs;
}

pub fn hCoprocessorSegmentOverrun(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGFPE)
        ) catch {};
        return regs;
    }
    if (true) @panic("hCoprocessorSegmentOverrun");
    return regs;
}

pub fn hInvalidTSS(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    if (true) @panic("hInvalidTSS");
    return regs;
}

pub fn hSegmentNotPresent(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGBUS)
        ) catch {};
        return regs;
    }
    if (true) @panic("hSegmentNotPresent");
    return regs;
}

pub fn hStackSegmentFault(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGBUS)
        ) catch {};
        return regs;
    }
    if (true) @panic("hStackSegmentFault");
    return regs;
}

pub fn hGeneralProtectionFault(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    kernel.logger.ERROR("PID {d}\n", .{kernel.task.current.pid});
    regs.dump();
    dbg.traceStackTrace(20);
    if (true) @panic("hGeneralProtectionFault");
}

pub fn hPageFault(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGSEGV)
        ) catch {};
        return regs;
    }
    var addr: u32 = 0;
    addr = arch.vmm.getCR2();
    arch.cpu.disableInterrupts();
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
    regs.dump();
    dbg.traceStackTrace(20);
    while (true) {}
    if (true) @panic("hPageFault");
}

pub fn hReserved_1(regs: *Regs) *Regs {
    if (true) @panic("hReserved_1");
    return regs;
}

pub fn hx87FloatingPointException(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGFPE)
        ) catch {};
        return regs;
    }
    if (true) @panic("hx87FloatingPointException");
    return regs;
}

pub fn hAlignmentCheck(regs: *Regs) *Regs {
    if (regs.isRing3()) {
        _ = kernel.kill(
            @intCast(kernel.task.current.pid),
            @intFromEnum(Signal.SIGBUS)
        ) catch {};
        return regs;
    }
    if (true) @panic("hAlignmentCheck");
    return regs;
}

pub fn hMachineCheck(regs: *Regs) *Regs {
    if (true) @panic("hMachineCheck");
    return regs;
}

pub fn hSIMDFloatingPointException(regs: *Regs) *Regs {
    if (true) @panic("hSIMDFloatingPointException");
    return regs;
}

pub fn hVirtualizationException(regs: *Regs) *Regs {
    if (true) @panic("hVirtualizationException");
    return regs;
}

pub fn hControlProtectionException(regs: *Regs) *Regs {
    if (true) @panic("hControlProtectionException");
    return regs;
}

pub fn hReserved_2(regs: *Regs) *Regs {
    if (true) @panic("hReserved_2");
    return regs;
}

pub fn hReserved_3(regs: *Regs) *Regs {
    if (true) @panic("hReserved_3");
    return regs;
}

pub fn hReserved_4(regs: *Regs) *Regs {
    if (true) @panic("hReserved_4");
    return regs;
}

pub fn hReserved_5(regs: *Regs) *Regs {
    if (true) @panic("hReserved_5");
    return regs;
}

pub fn hReserved_6(regs: *Regs) *Regs {
    if (true) @panic("hReserved_6");
    return regs;
}

pub fn hReserved_7(regs: *Regs) *Regs {
    if (true) @panic("hReserved_7");
    return regs;
}

pub fn hHypervisorInjectionException(regs: *Regs) *Regs {
    if (true) @panic("hHypervisorInjectionException");
    return regs;
}

pub fn hVMMCommunicationException(regs: *Regs) *Regs {
    if (true) @panic("hVMMCommunicationException");
    return regs;
}

pub fn hSecurityException(regs: *Regs) *Regs {
    if (true) @panic("hSecurityException");
    return regs;
}

pub fn hReserved_8(regs: *Regs) *Regs {
    if (true) @panic("hReserved_8");
    return regs;
}

const ExceptionHandlers = std.EnumMap(
    Exceptions,
    *const fn (regs: *Regs) *Regs
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
