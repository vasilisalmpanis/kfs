const multiboot = @import("arch").multiboot;
const std = @import("std");

const COMMAND_LINE_SIZE = 1024;
var cmdline_buf: [COMMAND_LINE_SIZE]u8 = undefined;
var cmdline: []const u8 = "";

pub fn init(boot_info: *multiboot.Multiboot) void {
    const tag = boot_info.getTag(multiboot.TagBootCommandLine) orelse return;
    const raw: [*:0]const u8 = @ptrFromInt(@intFromPtr(tag) + 8);
    const src = std.mem.span(raw);
    const len = @min(src.len, COMMAND_LINE_SIZE);
    @memcpy(cmdline_buf[0..len], src[0..len]);
    cmdline = cmdline_buf[0..len];
}

pub fn get(name: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, cmdline, ' ');
    while (it.next()) |param| {
        if (std.mem.startsWith(u8, param, name) and
            param.len > name.len and param[name.len] == '=')
            return param[name.len + 1 ..];
    }
    return null;
}

pub fn has(name: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, cmdline, ' ');
    while (it.next()) |param| {
        if (std.mem.eql(u8, param, name)) return true;
    }
    return false;
}
