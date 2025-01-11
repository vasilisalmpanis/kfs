const mem = @import("std").mem;
const debug = @import("debug.zig");
const system = @import("arch").system;
const printf = @import("printf.zig").printf;
const screen = @import("screen.zig");
const tty = @import("tty.zig");

pub const Shell = struct {    
    pub fn init() *Shell {
        var shell = Shell{};
        return &shell;
    }

    pub fn handleInput(self: *Shell, input: []const u8) void {
        _ = self;
        if (mem.eql(u8, input, "help")) {
            printf(\\
                \\available commands:
                \\  stack: print stack trace
                \\  reboot: reboot pc
                \\  42: print 42
                \\  [color name]: change input color
                \\  help: print this message
                \\
                , .{});
        } else if (mem.eql(u8, input, "stack")) {
            debug.TraceStackTrace(10);
        } else if (mem.eql(u8, input, "reboot")) {
            system.reboot();
        } else if (mem.eql(u8, input, "halt")) {
            system.halt();
        } else if (mem.eql(u8, input, "42")) {
            screen.current_tty.?.print42();
        } else if (mem.eql(u8, input, "red")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Red, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "green")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Green, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "blue")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Blue, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "orange")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Brown, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "magenta")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Magenta, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "white")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.White, tty.ConsoleColors.Black));
        } else if (mem.eql(u8, input, "black")) {
            screen.current_tty.?.setColor(tty.vga_entry_color(tty.ConsoleColors.Black, tty.ConsoleColors.Black));
        } else {
            printf("Command not known: \"{s}\".\nInput \"help\" to get available commands.\n", .{input});
        }
    }
};
