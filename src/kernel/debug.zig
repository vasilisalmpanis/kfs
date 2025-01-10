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
    while (frame < maxFrames and @intFromPtr(stk) > 0) : (frame += 1) {
        if (stk != null) {
            printf("  0x{x}     \n", .{ stk.?.eip });
        }
        stk = stk.?.ebp;
    }

}
