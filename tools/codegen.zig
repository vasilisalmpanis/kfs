const std = @import("std");
const api = @import("modules");

pub export const stack_top: u32 = 0;

fn printIdentation(identation: u32, writer: *std.io.Writer) !void {
    for (0..identation) |_| {
        try writer.print(" ", .{});
    }
}

fn printStruct(
    identation: u32,
    name: []const u8,
    str: std.builtin.Type.Struct,
    writer: *std.io.Writer,
    parent_val: type,
    visited: *std.StringHashMap(void),
    allocator: std.mem.Allocator,
) anyerror!void {
    const type_name = @typeName(parent_val);

    if (visited.contains(type_name))
        return;

    try visited.put(type_name, {});

    try printIdentation(identation, writer);
    try writer.print("pub const {s} = struct {{\n", .{name});
    inline for (str.decls) |decl| {
        const field_name = decl.name;
        const field_val = @field(parent_val, field_name);
        if (@TypeOf(field_val) != type)
            continue;
        const ti = @typeInfo(field_val);

        switch (ti) {
            .@"struct" => |cap| {
                try printStruct(
                    identation + 4,
                    field_name,
                    cap,
                    writer,
                    field_val,
                    visited,
                    allocator,
                );
                try writer.writeAll("\n");
            },
            else => {}
        }
    }
    std.debug.print("Struct {s}\n", .{name});
    inline for (str.fields) |field| {
        switch (@typeInfo(field.type)) {
            .@"struct" => |_t| {
                try printStruct(
                    identation + 4,
                    field.name,
                    _t,
                    writer,
                    field.type,
                    visited,
                    allocator,
                );
            },
            else => {
                try printIdentation(identation + 4, writer);
                const field_type_name = @typeName(field.type);
                try writer.print("{s}: {s},\n", .{field.name, field_type_name});
            }
        }
    }
    try printIdentation(identation, writer);
    try writer.print("}};\n", .{});
    try writer.flush();
}

// try interface.print("pub const {s} = struct {{\n", .{field_name});
// std.debug.print("\nStruct Name {s}\n", .{field_name});
// inline for (cap.fields) |f| {
//     const type_name = @typeName(f.type);
//     std.debug.print("type name {s}\n", .{type_name});
//     try writer.interface.print("    {s}:", .{f.name});
//     var tokens = std.mem.splitScalar(u8, type_name, ' ');
//     while (tokens.next()) |_token| {
//         std.debug.print("Token {s}\n", .{_token});
//         const token = std.mem.trim(u8, _token, " \t");
//         if (std.mem.lastIndexOf(u8, token, ".")) |idx| {
//             if (!std.mem.startsWith(u8, token, "std")) {
//                 try writer.interface.print(" {s}", .{token[idx + 1..]});
//             } else {
//                 try writer.interface.print(" {s}", .{token});
//             }
//         } else {
//             try writer.interface.print(" {s}", .{token});
//         }
//
//     }
//     try writer.interface.print(",\n", .{});
// }

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.debug.print("Usage: {s} <output_file>\n", .{args[0]});
        return error.InvalidArgs;
    }
    
    const output_path = args[1];
    std.debug.print("{s}\n", .{output_path});
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
   
    var buff: [4096]u8 = .{0} ** 4096;
    var writer = file.writer(buff[0..4096]);
    
    try writer.interface.writeAll("// Auto-generated kernel type interface\n\n");
    const interface = &writer.interface;
    
    // Create the visited map
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();
    
    switch (@typeInfo(api)) {
        .@"struct" => |_t| {
            std.debug.print("Struct {any}\n", .{_t});
            inline for (_t.decls) |decl| {
                const field_name = decl.name;
                const field_val = @field(api, field_name);
                if (@TypeOf(field_val) != type)
                    continue;
                const ti = @typeInfo(field_val);

                switch (ti) {
                .@"struct" => |cap| {
                    try printStruct(
                        0,
                        field_name, 
                        cap,
                        interface,
                        field_val,
                        &visited,    // Pass visited map
                        allocator,   // Pass allocator
                    );
                    try interface.writeAll("\n");
                },
                else => {}
            }
            }
        },
        else => {
            std.debug.print("default {any}\n", .{@typeInfo(@TypeOf(api))});
        },
    }
    try interface.flush();
}
