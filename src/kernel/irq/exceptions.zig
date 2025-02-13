const regs_t = @import("arch").regs;
const std = @import("std");
const register_exception_handler = @import("./manage.zig").register_exception_handler;

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

fn hDivisionError(regs: *regs_t) void {
    _ = regs;
    @panic("Division by zero");
}

fn hDebug(regs: *regs_t) void {
    _ = regs;
    @panic("Debug");
}

pub fn hNonMaskableInterrupt(regs: *regs_t) void {
    _ = regs;
    @panic("hNonMaskableInterrupt");
}

pub fn hBreakpoint(regs: *regs_t) void {
    _ = regs;
}

pub fn hOverflow(regs: *regs_t) void {
    _ = regs;
}

pub fn hBoundRangeExceeded(regs: *regs_t) void {
    _ = regs;
    @panic("hBoundRangeExceeded");
}

pub fn hInvalidOpcode(regs: *regs_t) void {
    _ = regs;
    @panic("hInvalidOpcode");
}

pub fn hDeviceNotAvailable(regs: *regs_t) void {
    _ = regs;
    @panic("hDeviceNotAvailable");
}

pub fn hDoubleFault(regs: *regs_t) void {
    _ = regs;
    @panic("hDoubleFault");
}

pub fn hCoprocessorSegmentOverrun(regs: *regs_t) void {
    _ = regs;
    @panic("hCoprocessorSegmentOverrun");
}

pub fn hInvalidTSS(regs: *regs_t) void {
    _ = regs;
    @panic("hInvalidTSS");
}

pub fn hSegmentNotPresent(regs: *regs_t) void {
    _ = regs;
    @panic("hSegmentNotPresent");
}

pub fn hStackSegmentFault(regs: *regs_t) void {
    _ = regs;
    @panic("hStackSegmentFault");
}

pub fn hGeneralProtectionFault(regs: *regs_t) void {
    _ = regs;
    @panic("hGeneralProtectionFault");
}

pub fn hPageFault(regs: *regs_t) void {
    _ = regs;
    @panic("hPageFault");
}

pub fn hReserved_1(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_1");
}

pub fn hx87FloatingPointException(regs: *regs_t) void {
    _ = regs;
    @panic("hx87FloatingPointException");
}

pub fn hAlignmentCheck(regs: *regs_t) void {
    _ = regs;
    @panic("hAlignmentCheck");
}

pub fn hMachineCheck(regs: *regs_t) void {
    _ = regs;
    @panic("hMachineCheck");
}

pub fn hSIMDFloatingPointException(regs: *regs_t) void {
    _ = regs;
    @panic("hSIMDFloatingPointException");
}

pub fn hVirtualizationException(regs: *regs_t) void {
    _ = regs;
    @panic("hVirtualizationException");
}

pub fn hControlProtectionException(regs: *regs_t) void {
    _ = regs;
    @panic("hControlProtectionException");
}

pub fn hReserved_2(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_2");
}

pub fn hReserved_3(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_3");
}

pub fn hReserved_4(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_4");
}

pub fn hReserved_5(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_5");
}

pub fn hReserved_6(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_6");
}

pub fn hReserved_7(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_7");
}

pub fn hHypervisorInjectionException(regs: *regs_t) void {
    _ = regs;
    @panic("hHypervisorInjectionException");
}

pub fn hVMMCommunicationException(regs: *regs_t) void {
    _ = regs;
    @panic("hVMMCommunicationException");
}

pub fn hSecurityException(regs: *regs_t) void {
    _ = regs;
    @panic("hSecurityException");
}

pub fn hReserved_8(regs: *regs_t) void {
    _ = regs;
    @panic("hReserved_8");
}

const ExceptionHandlers = std.EnumMap(
    Exceptions,
    *const fn (regs: *regs_t) void
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
        register_exception_handler(
            idx,
            @ptrCast(ExceptionHandlers.get(@enumFromInt(idx)))
        );
    }
}
