const std = @import("std");
const kernel = @import("main.zig");

extern const kallsyms_string_table: [*]const u8;
extern const kallsyms_addresses: [*]const u32;
extern const kallsyms_string_indices: [*]const u32;
extern const kallsyms_count: u32;
extern const kallsyms_string_table_size: u32;

pub fn get_symbol_name(index: u32) []const u8 {
    if (index >= kallsyms_count) return "";
    
    const start = kallsyms_string_indices[index];
    var end = start;
    
    while (end < kallsyms_string_table_size and kallsyms_string_table[end] != 0) {
        end += 1;
    }
    
    return kallsyms_string_table[start..end];
}

pub fn dump() void {
    kernel.logger.INFO("SYMBOLS COUNT: {d}\n", .{kallsyms_count});
    kernel.logger.INFO("STRING TABLE SIZE: {d}\n", .{kallsyms_string_table_size});

    for (0..kallsyms_count) |i| {
        const addr = kallsyms_addresses[i];
        const name = get_symbol_name(@intCast(i));
        kernel.logger.INFO("[{d}] 0x{x}: {s}\n", .{ i, addr, name });
    }
}
