const krn = @import("../main.zig");
const arch = @import("arch");

pub fn mkdir(
    path_name: [*]u8,
    mode: u32,
) i32 {
    _ = path_name;
    _ = mode;
    return 0;
}
