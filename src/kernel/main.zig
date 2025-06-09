const eql = @import("std").mem.eql;
const TTY = @import("tty.zig");
const Keyboard = @import("drivers").Keyboard;
const system = @import("arch").system;
const gdt = @import("arch").gdt;
const screen = @import("screen.zig");
const debug = @import("debug.zig");
const printf = @import("printf.zig").printf;


pub fn trace() void {
    debug.TraceStackTrace(10);
}

pub const MultibootInfo = packed struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms_0: u32,
    syms_1: u32,
    syms_2: u32,
    syms_3: u32,
    mmap_length: u32,
    mmap_addr: u32,
    drives_length: u32,
    drives_addr: u32,
    config_table: u32,
    boot_loader_name: u32,
    apm_table: u32,
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
};

pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub const Serial = struct {
    addr: u16 = 0x3F8, // COM1
    pub fn init() Serial {
        const serial = Serial{};
        outb(serial.addr + 1, 0x00);
        outb(serial.addr + 3, 0x80);
        outb(serial.addr, 0x01);
        outb(serial.addr + 1, 0x00);
        outb(serial.addr + 3, 0x03);
        outb(serial.addr + 2, 0xC7);
        outb(serial.addr + 1, 0x01);
        return serial;
    }

    pub fn putchar(self: *Serial, char: u8) void {
        while ((inb(self.addr + 5) & 0x20) == 0) {}
        outb(self.addr, char);
    }

    pub fn print(self: *Serial, message: []const u8) void {
        for (message) |char| {
            self.putchar(char);
        }
    }
};

const std = @import("std");

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


const BLACK = "\x1b[1;30m";
const RED = "\x1b[1;31m";
const GREEN = "\x1b[1;32m";
const YELLOW = "\x1b[1;33m";
const BLUE = "\x1b[1;34m";
const MAGENTA = "\x1b[1;35m";
const CYAN = "\x1b[1;36m";
const WHITE = "\x1b[1;37m";
const DEFAULT = "\x1b[1;39m";

var s: Serial = undefined;
var logger: Logger = undefined;

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

        var buffer: [1024]u8 = undefined;
        const color = switch (level) {
            .DEBUG => BLUE,
            .INFO => GREEN,
            .WARN => YELLOW,
            .ERROR => RED
        };
        const formatted_log = try std.fmt.bufPrint(&buffer, 
            "{s}[{s}]: " ++
                format ++
                DEFAULT ++
                if (format[format.len - 1] == '\n') "" else "\n",
            .{
                color,
                @tagName(level)
            } ++ args
        );
        s.print(formatted_log);
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

export fn kernel_main(magic: u32, addr: u32) noreturn {
    s = Serial.init();
    logger = Logger.init(.INFO);
    logger.INFO("hello\n", .{});
    if (magic != 0x2BADB002) {
        logger.INFO("magic {x}\n", .{magic});
        system.halt();
    }
    const info: *MultibootInfo = @ptrFromInt(addr);
    gdt.gdt_init();
    var scrn : *screen.Screen = screen.Screen.init();
    logger.INFO("hello\n", .{});
    // printf("GDT INITIALIZED\n", .{});
    inline for (@typeInfo(TTY.ConsoleColors).@"enum".fields) |f| {
        const clr: u8 = TTY.vga_entry_color(@field(TTY.ConsoleColors, f.name), TTY.ConsoleColors.Black);
        screen.current_tty.?.print("42\n", clr, false);
    }
    printf("\n", .{});
    var keyboard = Keyboard.init();
    logger.WARN("addr {x}\n", .{info.framebuffer_addr});

    const virt: [*]u32 = @ptrFromInt(@as(u32, @truncate(info.framebuffer_addr)));
    @memset(
        virt[0..info.framebuffer_width * info.framebuffer_height], 
        0xFF0000,
    );

    while (true) {
        const input = keyboard.get_input();
        switch (input[0]) {
            'R' => system.reboot(),
            'M' => screen.current_tty.?.move(input[1]),
            'S' => trace(),
            'C' => screen.current_tty.?.clear(),
            'T' => scrn.switch_tty(input[1]),
            else => if (input[1] != 0) screen.current_tty.?.print(&.{input[1]}, null, true)
        }
    }
}
