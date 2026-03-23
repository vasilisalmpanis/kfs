const lookupSymbol = @import("./symbols.zig").lookupSymbol;
const krn = @import("kernel");
const arch = @import("arch");
const std = @import("std");

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
            krn.logger.ERROR("  0x{x}: {s}\n", .{
                stk.?.eip,
                if(lookupSymbol(stk.?.eip)) |sym| sym else "?"
            });
        }
        stk = stk.?.ebp;
    }
}

fn framePtrInTaskStack(task: *const krn.task.Task, ebp_val: usize) bool {
    const lo = task.stack_bottom;
    const hi = task.stack_bottom + krn.STACK_SIZE;
    return ebp_val >= lo and ebp_val + @sizeOf(StackFrame) <= hi;
}

pub fn formatKernelStackTraceForTask(out: []u8, maxFrames: u32, task: *krn.task.Task) usize {
    var pos: usize = 0;
    const header = "Stack trace:\n";
    if (header.len <= out.len) {
        @memcpy(out[0..header.len], header);
        pos = header.len;
    } else {
        return 0;
    }

    const start_ebp: usize = if (task == krn.task.current)
        arch.cpu.getStackFrameAddr()
    else
        @intCast(task.regs.ebp);

    var stk: ?*StackFrame = if (start_ebp != 0 and framePtrInTaskStack(task, start_ebp))
        @ptrFromInt(start_ebp)
    else {
        var line: [96]u8 = undefined;
        const line_slice = std.fmt.bufPrint(
            line[0..],
            "  (no frame chain) saved_eip=0x{x} saved_ebp=0x{x}\n",
            .{ task.regs.eip, task.regs.ebp },
        ) catch return pos;
        if (pos + line_slice.len > out.len)
            return pos;
        @memcpy(out[pos..][0..line_slice.len], line_slice);
        return pos + line_slice.len;
    };

    var frame: u32 = 0;
    while (frame < maxFrames and stk != null) : (frame += 1) {
        const ebp_u: usize = @intFromPtr(stk);
        if (!framePtrInTaskStack(task, ebp_u))
            break;
        const eip = stk.?.eip;
        const sym = if (lookupSymbol(eip)) |s| s else "?";
        var line: [160]u8 = undefined;
        const line_slice = std.fmt.bufPrint(
            line[0..],
            "  0x{x}: {s}\n",
            .{ eip, sym },
        ) catch break;
        if (pos + line_slice.len > out.len)
            break;
        @memcpy(out[pos..][0..line_slice.len], line_slice);
        pos += line_slice.len;
        stk = stk.?.ebp;
    }
    return pos;
}
