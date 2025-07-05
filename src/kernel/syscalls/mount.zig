const krn = @import("../main.zig");
const arch = @import("arch");

pub fn mount(
    dev_name: [*]u8,
    dir_name: [*]u8,
    fs_type: [*]u8,
    new_flags: u32,
    data: *anyopaque
) i32 {
    _ = dev_name;
    _ = dir_name;
    _ = fs_type;
    _ = new_flags;
    _ = data;
    return 0;
}
