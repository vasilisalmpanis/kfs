const std = @import("std");
const modules = @import("modules");

pub export const stack_top: u32 = 0;
var allocator: std.mem.Allocator = undefined;
var visited_registry: std.StringHashMap([]const u8) = undefined;

fn printIdentation(identation: u32, writer: *std.io.Writer) !void {
    for (0..identation) |_| {
        try writer.print(" ", .{});
    }
}

fn constructKey(typ: anytype) ![]const u8 {
    var res: []const u8 = undefined;
    var buf: []const u8 = undefined;

    const key = @typeName(typ);

    if (std.mem.lastIndexOf(u8, key, ".")) |idx| {
        res = try std.fmt.allocPrint(allocator, "{s}", .{key[idx + 1..]});
    } else {
        res = try std.fmt.allocPrint(allocator, "{s}", .{key});
    }

    const ti = @typeInfo(typ);
    switch (ti) {
        .@"struct" => |_s| {
            for (_s.decls) |decl| {
                buf = res;
                res = try std.fmt.allocPrint(allocator, "{s}.{s}", .{res, decl.name});
                allocator.free(buf);
            }
        },
        else => {}
    }
    return res;
}

fn printType(visited_key: [] const u8, type_name: []const u8, writer: *std.Io.Writer) !void {
    if (std.mem.lastIndexOf(u8, type_name, ".")) |idx| {
        if (visited_registry.get(visited_key)) |_to| {
            try writer.print("{s}.{s}", .{_to, type_name[idx + 1..]});
        } else {
            try writer.print("std.{s}", .{type_name});
        }
    } else {
        try writer.print("{s}", .{type_name});
    }
}

fn printStructLayout(struct_type: std.builtin.Type.Struct, struct_name: []const u8, writer: *std.Io.Writer, identation: u32) !void {
    try printIdentation(identation, writer);
    try writer.print("pub const {s} = ", .{struct_name});
    switch (struct_type.layout) {
        .auto => {},
        .@"extern" => {
            try writer.print("extern ", .{});
        },
        .@"packed" => {
            try writer.print("packed ", .{});
        },
    }
    try writer.print("struct {{\n", .{});
}

fn findTypeStart(str: []const u8) usize {
    var idx = str.len - 1;
    while (idx >= 0) {
        if (std.mem.containsAtLeastScalar(u8, " *?!", 1, str[idx]))
            return idx + 1;
        if (idx == 0)
            break ;
        idx -= 1;
    }
    return 0;
}

fn printDefaultValue(value: anytype, writer: *std.Io.Writer) anyerror!void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int => {
            try writer.print("= {d}", .{value});
        },
        .float => {
            try writer.print("= {d}", .{value});
        },
        .bool => {
            try writer.print("= {s}", .{if (value) "true" else "false"});
        },
        .comptime_int => {
            try writer.print("= {d}", .{value});
        },
        .comptime_float => {
            try writer.print("= {d}", .{value});
        },
        .null => {
            try writer.print("= null", .{});
        },
        .undefined => {
            try writer.print("= undefined", .{});
        },
        .optional => {
            try writer.print("= null", .{});
        },
        // TODO
        else => {}
    }
}

fn cleanType(typ: type, writer: *std.Io.Writer) anyerror!void {
    const typeinfo = @typeInfo(typ);
    switch (typeinfo) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one =>{
                    try writer.print("*", .{});
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
            inline for (_fn.params, 1..) |param, idx| {
                if (param.type) |_t| {
                    try cleanType(_t, writer);
                }
                if (idx < _fn.params.len)
                    try writer.print(", ", .{});
            }
            try writer.print(") ", .{});
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
            if (std.mem.indexOf(u8, replace_from, "(")) |par_o| {
                const fn_name = replace_from[0..par_o];
                var vis_key = fn_name;
                if (std.mem.lastIndexOf(u8, vis_key, ".")) |idx| {
                    vis_key = vis_key[idx + 1 ..];
                }
                try printType(vis_key, fn_name, writer);
                try writer.writeAll("(");

                var args_str: []const u8 = replace_from[par_o + 1 ..];
                if (std.mem.lastIndexOf(u8, args_str, ")")) |par_c| {
                    args_str = args_str[0..par_c];
                    var it = std.mem.splitScalar(u8, args_str, ',');
                    while (it.next()) |arg| {
                        const type_start = findTypeStart(arg);

                        try writer.writeAll(arg[0..type_start]);
                        try writer.flush();

                        var _key = arg[type_start..];
                        if (std.mem.lastIndexOf(u8, _key, ".")) |idx| {
                            _key = _key[idx + 1 ..];
                        }
                        try printType(_key, arg[type_start..], writer);

                        if (it.rest().len > 0)
                            try writer.writeAll(", ");
                    }
                }

                try writer.writeAll(")");
            } else {
                const visited_key = try constructKey(typ);
                defer allocator.free(visited_key);
                try printType(visited_key, replace_from, writer);
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
    first_run: bool,
) anyerror!void {

    const visited_key = try constructKey(struct_val);
    if (visited.contains(visited_key)) {
        allocator.free(visited_key);
        return;
    }

    if (first_run) {
        const prefix_copy = try allocator.alloc(u8, name_prefix.len);
        @memcpy(prefix_copy[0..], name_prefix[0..]);
        try visited.put(visited_key, prefix_copy);
        if (!visited.contains(struct_name)) {
            const name_copy = try allocator.dupe(u8, struct_name);
            const prefix_copy_copy = try allocator.dupe(u8, prefix_copy);
            try visited.put(name_copy, prefix_copy_copy);
        }
    } else {
        try visited.put(visited_key, "");
    }

    switch (curr_type) {
        .@"struct" => |struct_type| {

            if (!first_run) {
                try printStructLayout(struct_type, struct_name, writer, identation);
            }
            inline for (struct_type.decls) |decl| {
                const decl_name = decl.name;
                const decl_val = @field(struct_val, decl_name);
                if (@TypeOf(decl_val) != type) {
                    const temp_ti = @typeInfo(@TypeOf(decl_val));
                    switch (temp_ti) {
                        .@"fn" => |function| {
                            if (!first_run) {
                                if (function.calling_convention.eql(std.builtin.CallingConvention.c)) {
                                    try printIdentation(identation + 4, writer);
                                    try writer.print("pub extern fn {s}(", .{decl_name});
                                    inline for (function.params, 1..) |param, idx| {
                                        if (param.type) |_t| {
                                            try cleanType(_t, writer);
                                        }
                                        if (idx < function.params.len)
                                            try writer.print(", ", .{});
                                    }
                                    try writer.print(")", .{});
                                    if (function.return_type) |ret| {
                                        try cleanType(ret, writer);
                                    } else {
                                        try writer.print(" void", .{});
                                    }
                                    try writer.writeAll(";\n");
                                }
                            }
                        },
                        else => {
                        }
                    }
                    continue;
                }
                const ti = @typeInfo(decl_val);

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
                            decl_name,
                            ti,
                            writer,
                            decl_val,
                            visited,
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
                    if (field.defaultValue()) |value| {
                        try printDefaultValue(value, writer);
                    }
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
    allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.debug.print("Usage: {s} <output_file>\n", .{args[0]});
        return error.InvalidArgs;
    }
    
    const output_path = args[1];
    const file = try std.fs.cwd().createFile(output_path, std.fs.File.CreateFlags{
        .read = true,
    });
    defer file.close();
   
    var buff: [4096]u8 = .{0} ** 4096;
    var writer = file.writer(buff[0..4096]);
    
    try writer.interface.writeAll(
        \\// Auto-generated kernel type interface
        \\const std = @import("std");
        \\
        \\
    );
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
                    false
                );
                try interface.writeAll("\n");
            }
            var it = visited.iterator();
            while (it.next()) |item| {
                allocator.free(item.value_ptr.*);
                allocator.free(item.key_ptr.*);
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
        allocator.free(item.key_ptr.*);
    }
    visited_registry.deinit();
}
