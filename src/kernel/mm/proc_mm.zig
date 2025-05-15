const lst = @import("../utils/list.zig");

const VMA = struct {
    start: u32,
    end: u32,
    mm: ?*TaskMm,
    flags: u32,
    list: lst.ListHead,
};

const TaskMm = struct {
    stack_bottom: u32,
    bss: u32 = 0,
    vas: u32 = 0,
    vmas: ?*VMA = null,
};
