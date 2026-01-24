const printf = @import("./printf.zig").printf;
const lookupSymbol = @import("./symbols.zig").lookupSymbol;
const krn = @import("kernel");
const arch = @import("arch");

const StackFrame = struct {
    ebp : ?*StackFrame = null,
    eip : usize,

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
    var stk : ?*StackFrame = @ptrFromInt(arch.cpu.getStackFrameAddr());
    krn.logger.INFO("Stack Trace:\n",.{});
    var frame : u32 = 0;
    // unwind the stack
    while (frame < maxFrames and stk != null) : (frame += 1) {
        if (stk != null) {
            krn.logger.INFO("  0x{x}: {s}\n", .{
                stk.?.eip,
                if(lookupSymbol(stk.?.eip)) |sym| sym else "?"
            });
        }
        stk = stk.?.ebp;
    }
}
