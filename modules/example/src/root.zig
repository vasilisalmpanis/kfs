const std = @import("std");

pub extern fn kmalloc(size: u32) u32;

pub export fn add() u32 {
    _ = kmalloc(100);
    return 0;
}

pub export fn _init() u32 {
    _ = kmalloc(43);
    return 100;
}
