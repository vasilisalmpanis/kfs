// const std = @import("std");

// pub extern fn kmalloc(size: u32) u32;

pub fn add(a: u32, b: u32) u32 {
    return a + b;
}

export fn example_init() linksection(".init") callconv(.c) u32 {
    // _ = kmalloc(43);
    return add(55, 35);
    // return 50;
}

export fn example_exit() linksection(".exit") callconv(.c) void {
}
