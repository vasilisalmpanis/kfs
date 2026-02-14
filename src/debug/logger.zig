const std = @import("std");
const krn = @import("kernel");
const arch = @import("arch");

pub const LogLevel = enum {
    DEBUG,
    INFO,
    WARN,
    ERROR,
};

pub const LogDestination = enum {
    SERIAL,
    SCREEN,
};


pub const BLACK = "\x1b[1;30m";
pub const RED = "\x1b[1;31m";
pub const GREEN = "\x1b[1;32m";
pub const YELLOW = "\x1b[1;33m";
pub const BLUE = "\x1b[1;34m";
pub const MAGENTA = "\x1b[1;35m";
pub const CYAN = "\x1b[1;36m";
pub const WHITE = "\x1b[1;37m";
pub const DEFAULT = "\x1b[1;39m";

pub const Logger = struct {
    log_level: LogLevel,

    pub fn init(log_level: LogLevel) Logger {
        return Logger{
            .log_level = log_level,
        };
    }

    pub fn log(
        self: *Logger,
        level: LogLevel,
        comptime format: []const u8,
        args: anytype
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.log_level)) return;

        const color = switch (level) {
            .DEBUG => BLUE,
            .INFO => GREEN,
            .WARN => YELLOW,
            .ERROR => RED
        };
        if (arch.cpu.areIntEnabled()) {
            const formatted_log = try std.fmt.allocPrint(krn.mm.kernel_allocator.allocator(),
                "{s}[{t}]: " ++
                format ++
                DEFAULT ++
                if (format[format.len - 1] == '\n') "" else "\n",
                .{
                    color,
                    level,
                } ++ args
            );
            krn.serial.print(formatted_log);
            krn.mm.kfree(formatted_log.ptr);
        } else {
            var buf: [512]u8 = undefined;
            const formatted_log = std.fmt.bufPrint(buf[0..512],
                "{s}[{t}]: " ++
                format ++
                DEFAULT ++
                if (format[format.len - 1] == '\n') "" else "\n",
                .{
                    color,
                    level,
                } ++ args
            ) catch "";
            krn.serial.print(formatted_log);
        }
    }

    pub fn DEBUG(
        self: *Logger,
        comptime format: []const u8,
        args: anytype
    ) void {
        self.log(.DEBUG, format, args) catch {};
    }

    pub fn INFO(
        self: *Logger,
        comptime format: []const u8,
        args: anytype
    ) void {
        self.log(.INFO, format, args) catch {};
    }

    pub fn WARN(
        self: *Logger,
        comptime format: []const u8,
        args: anytype
    ) void {
        self.log(.WARN, format, args) catch {};
    }

    pub fn ERROR(
        self: *Logger,
        comptime format: []const u8,
        args: anytype
    ) void {
        self.log(.ERROR, format, args) catch {};
    }
};
