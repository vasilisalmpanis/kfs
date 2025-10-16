const std = @import("std");
const modules = @import("modules");

pub export const stack_top: u32 = 0;

fn printIdentation(identation: u32, writer: *std.io.Writer) !void {
    for (0..identation) |_| {
        try writer.print(" ", .{});
    }
}

var visited_registry: std.StringHashMap([]const u8) = undefined;

fn cleanType(typ: type) void {
    const typeinfo = @typeInfo(typ);
    switch (typeinfo) {
        .pointer => |ptr| {
            cleanType(ptr.child);
        },
        .optional => |op| {
            cleanType(op.child);
        },
        .array => |arr| {
            cleanType(arr.child);
        },
        .error_union => |err| {
            cleanType(err.payload);
        },
        .@"fn" => |_fn| {
            if (_fn.return_type) |ret| {
                cleanType(ret);
            }
            inline for (_fn.params) |param| {
                if (param.type) |_t| {
                    cleanType(_t);
                }
            }
        },
        .@"anyframe" => |_any| {
            if (_any.child) |_t| {
                cleanType(_t);            }
        },
        else => {
            std.debug.print("clean type: {s}\n", .{@typeName(typ)});
        }
    }
}

fn printStruct(
    name_prefix: []const u8,
    identation: u32,
    struct_name: []const u8,
    struct_type: std.builtin.Type.Struct,
    writer: *std.io.Writer,
    struct_val: type,
    visited: *std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    first_run: bool,
) anyerror!void {

    if (visited.contains(struct_name))
        return;

    if (first_run) {
        const prefix_copy = try allocator.alloc(u8, name_prefix.len);
        @memcpy(prefix_copy[0..], name_prefix[0..]);
        try visited.put(struct_name, prefix_copy);
    } else {
        try visited.put(struct_name, "");
    }

    if (first_run) {
        try printIdentation(identation, writer);
        try writer.print("pub const {s} = struct {{\n", .{struct_name});
    }
    inline for (struct_type.decls) |decl| {
        const field_name = decl.name;
        // std.debug.print("getting {s} in {s}", .{field_name, struct_name});
        const field_val = @field(struct_val, field_name);
        if (@TypeOf(field_val) != type)
            continue;
        const ti = @typeInfo(field_val);

        var prefix: []const u8 = struct_name;
        if (name_prefix.len != 0) {
            const _sl: []const []const u8 = &.{name_prefix, struct_name};
            prefix = try std.mem.join(allocator, ".", _sl);
        }

        switch (ti) {
            .@"struct" => |cap| {
                try printStruct(
                    prefix,
                    identation + 4,
                    field_name,
                    cap,
                    writer,
                    field_val,
                    visited,
                    allocator,
                    first_run
                );
                if (first_run)
                    try writer.writeAll("\n");
            },
            else => {}
        }
        if (name_prefix.len != 0)
            allocator.free(prefix);
    }
    std.debug.print("Struct {s}\n", .{struct_name});
    inline for (struct_type.fields) |field| {
        const field_type_name = @typeName(field.type);
        if (first_run) {
            try printIdentation(identation + 4, writer);
            try writer.print("{s}: {s},\n", .{field.name, field_type_name});
        } else {
            cleanType(field.type);
            // const ti = @typeInfo(field.type);
            // switch (ti) {

            //     else => {
            //         if (std.mem.lastIndexOf(u8, field_type_name, ".")) |idx| {
            //             var it = std.mem.splitBackwardsScalar(u8, field_type_name, ' ');
            //             if (it.next()) |last_seg| {
            //                 var to_replace = std.mem.replace(u8, last_seg, "anyerror!", "");
            //                 to_replace = std.mem.trimStart(u8, to_replace, "!");
            //                 to_replace = std.mem.trimStart(u8, to_replace, "?");
            //                 to_replace = std.mem.trimStart(u8, to_replace, "*");

            //                 const last_segment = field_type_name[idx + 1 ..];
            //                 if (visited_registry.get(last_segment)) |val| {
            //                     std.debug.print("Replace: {s} | {s} => {s}.{s}\n", .{field_type_name, to_replace, val, last_segment});
            //                 } else {
            //                     std.debug.print("Replace: {s} | {s} => std.{s}\n", .{field_type_name, to_replace, to_replace});
            //                 }
            //             }
            //         }
            //     }
            // }
        }
    }
    if(first_run) {
        try printIdentation(identation, writer);
        try writer.print("}};\n", .{});
        try writer.flush();
    }
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
    visited_registry = std.StringHashMap([]const u8).init(allocator);
    
    switch (@typeInfo(modules)) {
        .@"struct" => |_t| {
            inline for (_t.decls) |decl| {
                const field_name = decl.name;
                const field_val = @field(modules, field_name);

                if (@TypeOf(field_val) != type)
                    continue;

                const ti = @typeInfo(field_val);
                switch (ti) {
                    .@"struct" => |cap| {
                        try printStruct(
                            "",
                            0,
                            field_name, 
                            cap,
                            interface,
                            field_val,
                            &visited_registry,    // Pass visited map
                            allocator,   // Pass allocator
                            true
                        );
                        try interface.writeAll("\n");
                    },
                    else => {}
                }
            }
            var visited = std.StringHashMap([]const u8).init(allocator);
            defer visited.deinit();
            inline for (_t.decls) |decl| {
                const field_name = decl.name;
                const field_val = @field(modules, field_name);

                if (@TypeOf(field_val) != type)
                    continue;

                const ti = @typeInfo(field_val);
                switch (ti) {
                    .@"struct" => |cap| {
                        try printStruct(
                            "",
                            0,
                            field_name, 
                            cap,
                            interface,
                            field_val,
                            &visited,    // Pass visited map
                            allocator,   // Pass allocator
                            false
                        );
                        try interface.writeAll("\n");
                    },
                    else => {}
                }
            }
        },
        else => {
            std.debug.print("default {any}\n", .{@typeInfo(@TypeOf(modules))});
        },
    }
    try interface.flush();
    var it = visited_registry.iterator();
    while (it.next()) |item| {
        allocator.free(item.value_ptr.*);
    }
    visited_registry.deinit();
}
