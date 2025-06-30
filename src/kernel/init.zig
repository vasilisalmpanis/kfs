const std = @import("std");
const PAGE_OFFSET = @import("./main.zig").mm.PAGE_OFFSET;
// Import the linker symbols
extern var __init_call_start: u32;
extern var __init_call_end: u32;
extern var __init_call_early_start: u32;
extern var __init_call_early_end: u32;
extern var __init_call_device_start: u32;
extern var __init_call_device_end: u32;

// Not working for now.

// fn initcall(comptime section: []const u8, comptime func: anytype) void {
//     const S = struct {
//         const exported_data: *const fn() callconv(.c) void linksection(section) = func;
//     };
//     _ = S; // Force the struct to be analyzed
// }
//
// pub fn earlyInitcall(comptime func: InitCallFn) void {
//     registerInitcall(".init_call.early", func);
// }
//
// pub fn deviceInitcall(comptime func: InitCallFn) void {
//     registerInitcall(".init_call.device", func);
// }
//
// fn registerInitcall(comptime section: []const u8, comptime func: InitCallFn) void {
//     initcall(section, func);
// }

//
const InitCallFn = *const fn() callconv(.c)void;

// Function to call early init functions
fn call_early_init() void {
    const start_addr = @intFromPtr(&__init_call_early_start);
    const end_addr = @intFromPtr(&__init_call_early_end);
    
    const num_functions = (end_addr - start_addr) / @sizeOf(InitCallFn);
    const init_functions: [*]InitCallFn = @ptrFromInt(start_addr);

    for (0..num_functions) |i| {
        init_functions[i]();
    }
}

// Function to call device init functions
fn call_device_init() void {
    const start_addr = @intFromPtr(&__init_call_device_start);
    const end_addr = @intFromPtr(&__init_call_device_end);
    
    const num_functions = (end_addr - start_addr) / @sizeOf(InitCallFn);
    const init_functions: [*]InitCallFn = @ptrFromInt(start_addr);
    
    for (0..num_functions) |i| {
        init_functions[i]();
    }
}

pub fn do_initcall() void {
    @import("./main.zig").logger.INFO("doing early calls\n", .{});
    call_early_init();
    @import("./main.zig").logger.INFO("doing device calls\n", .{});
    call_device_init();
}
