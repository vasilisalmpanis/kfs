// const std = @import("std");
const types = @import("types");

// pub extern fn kmalloc(size: u32) u32;
//
pub extern fn print_serial(arr: [*]const u8, size: u32) void;
pub extern fn print_screen(arr: [*]const u8, size: u32) void;
pub var temp: u32 = 2;

pub fn add3(a: u32, b: u32) u32 {
    temp += a + b;
    const slice: []const u8 = "hello world\n";
    print_serial(slice.ptr, slice.len);
    print_screen(slice.ptr, slice.len);
    return temp;
}

pub fn add2(a: u32, b: u32) u32 {
    return add3(a, b);
}

pub fn add(a: u32, b: u32) u32 {
    return add2(a, b);
}

export fn example_init() linksection(".init") callconv(.c) u32 {
    _ = add(55, 35);
    const temp1: types.kernel.mm.proc_mm.MAP_TYPE = .SHARED;
    _ = temp1;
    return 0;
}

export fn example_exit() linksection(".exit") callconv(.c) void {
}
