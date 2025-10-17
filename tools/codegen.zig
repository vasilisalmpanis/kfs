const std = @import("std");
const modules = @import("modules");

pub export const stack_top: u32 = 0;

fn printIdentation(identation: u32, writer: *std.io.Writer) !void {
    for (0..identation) |_| {
        try writer.print(" ", .{});
    }
}

var visited_registry: std.StringHashMap([]const u8) = undefined;

fn cleanType(typ: type, writer: *std.Io.Writer) anyerror!void {
    const typeinfo = @typeInfo(typ);
    switch (typeinfo) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one =>{
                    try writer.print("* ", .{});
                },
                .many =>{
                    try writer.print("[*{s}]", .{if (ptr.sentinel_ptr != null) ":0" else ""});
                },
                .slice => {
                    try writer.print("[]", .{});
                },
                else => {
                }
            }
            if (ptr.is_const) {
                try writer.print("const ", .{});
            }
            try cleanType(ptr.child, writer);
        },
        .vector => |vec| {
                try writer.print("[{d}]", .{vec.len});
                try cleanType(vec.child, writer);
        },
        .optional => |op| {
            try writer.print("?", .{});
            try cleanType(op.child, writer);
        },
        .array => |arr| {
            try writer.print("[{d}]", .{arr.len});
            try cleanType(arr.child, writer);
        },
        .error_union => |err| {
            try writer.print("anyerror!", .{});
            try cleanType(err.payload, writer);
        },
        .@"fn" => |_fn| {
            try writer.print("fn(", .{});
            inline for (_fn.params) |param| {
                if (param.type) |_t| {
                    try cleanType(_t, writer);
                }
                try writer.print(",", .{});
            }
            try writer.print(")", .{});
            if (_fn.return_type) |ret| {
                try cleanType(ret, writer);
            } else {
                try writer.print(" void", .{});
            }
        },
        .@"anyframe" => {
        },
        .int => |num| {
            const char: u8 = if (num.signedness == .signed) 'i' else 'u';
            try writer.print("{c}{d}", .{char, num.bits});
        },
        .float => |num| {
            try writer.print("f{d}", .{num.bits});
        },
        .bool => {
            try writer.print("bool", .{});
        },
        .void => {
            try writer.print("void", .{});
        },
        .null => {
            try writer.print("null", .{});
        },
        .undefined => {
            try writer.print("undefined", .{});
        },
        .@"opaque" => {
            try writer.print("anyopaque", .{});
        },
        .comptime_float => {
            try writer.print("comptime_float", .{});
        },
        .comptime_int => {
            try writer.print("comptime_int", .{});
        },
        .noreturn => {
            try writer.print("noreturn", .{});
        },
        else => {
            const replace_from = @typeName(typ);
            if (std.mem.lastIndexOf(u8, replace_from, ".")) |idx| {
                if (visited_registry.get(replace_from[idx + 1..])) |_to| {
                    try writer.print("{s}.{s}", .{_to, replace_from[idx + 1..]});
                } else {
                    try writer.print("std.{s}", .{replace_from});
                }
            }
        }
    }
}

fn printStruct(
    name_prefix: []const u8,
    identation: u32,
    struct_name: []const u8,
    curr_type: std.builtin.Type,
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

    switch (curr_type) {
        .@"struct" => |struct_type| {
            if (!first_run) {
                try printIdentation(identation, writer);
                try writer.print("pub const {s} = struct {{\n", .{struct_name});
            }
            inline for (struct_type.decls) |decl| {
                const field_name = decl.name;
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
                    .@"struct", .@"enum" => {
                        try printStruct(
                            prefix,
                            identation + 4,
                            field_name,
                            ti,
                            writer,
                            field_val,
                            visited,
                            allocator,
                            first_run
                        );
                        if (!first_run)
                            try writer.writeAll("\n");
                        },
                        else => {}
                }
                if (name_prefix.len != 0)
                    allocator.free(prefix);
            }
            inline for (struct_type.fields) |field| {
                if (!first_run) {
                    try printIdentation(identation + 4, writer);
                    try writer.print("{s}: ", .{field.name});
                    try cleanType(field.type, writer);
                    try writer.print(",\n", .{});
                }
            }
            if(!first_run) {
                try printIdentation(identation, writer);
                try writer.print("}};\n", .{});
                try writer.flush();
            }
        },
        .@"enum" => |en| {
            if (!first_run) {
                try printIdentation(identation, writer);
                try writer.print("pub const {s} = enum({s}) {{\n", .{struct_name, @typeName(en.tag_type)});
                inline for (en.fields) |field| {
                    try printIdentation(identation + 4, writer);
                    try writer.print("{s} = {d},\n", .{field.name, field.value});
                }
                if (!en.is_exhaustive) {
                    try printIdentation(identation + 4, writer);
                    try writer.print("_,\n", .{});
                }
                try printIdentation(identation, writer);
                try writer.print("}};\n\n", .{});
            }
        },
        else => {
        }
    }
}

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
    const file = try std.fs.cwd().createFile(output_path, std.fs.File.CreateFlags{
        .read = true,
    });
    defer file.close();
   
    var buff: [4096]u8 = .{0} ** 4096;
    var writer = file.writer(buff[0..4096]);
    
    try writer.interface.writeAll("// Auto-generated kernel type interface\n\n");
    const interface = &writer.interface;
    
    visited_registry = std.StringHashMap([]const u8).init(allocator);
    
    switch (@typeInfo(modules)) {
        .@"struct" => |_t| {
            inline for (_t.decls) |decl| {
                const field_name = decl.name;
                const field_val = @field(modules, field_name);

                if (@TypeOf(field_val) != type)
                    continue;

                const ti = @typeInfo(field_val);
                try printStruct(
                    "",
                    0,
                    field_name,
                    ti,
                    interface,
                    field_val,
                    &visited_registry,
                    allocator,
                    true
                );
            }
            var visited = std.StringHashMap([]const u8).init(allocator);
            defer visited.deinit();
            inline for (_t.decls) |decl| {
                const field_name = decl.name;
                const field_val = @field(modules, field_name);

                if (@TypeOf(field_val) != type)
                    continue;

                const ti = @typeInfo(field_val);
                try printStruct(
                    "",
                    0,
                    field_name,
                    ti,
                    interface,
                    field_val,
                    &visited,
                    allocator,
                    false
                );
                try interface.writeAll("\n");
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
