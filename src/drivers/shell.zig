const mem = @import("std").mem;
const debug = @import("debug");
const printf = @import("debug").printf;
const system = @import("arch").system;
const screen = @import("screen.zig");
const tty = @import("tty-fb.zig");

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
                \\  stack: Print the stack trace
                \\  reboot: Reboot the PC
                \\  shutdown: Power off the PC
                \\  halt: Halt the PC
                \\  42: Print 42
                \\  [color name]: Change the input color
                \\  help: Display this help message
                \\
                , .{});
        } else if (mem.eql(u8, input, "stack")) {
            debug.TraceStackTrace(10);
        } else if (mem.eql(u8, input, "reboot")) {
            system.reboot();
        } else if (mem.eql(u8, input, "shutdown")) {
            system.shutdown();
        } else if (mem.eql(u8, input, "halt")) {
            system.halt();
        } else if (mem.eql(u8, input, "42")) {
            // screen.current_tty.?.print42();
        } else if (mem.eql(u8, input, "red")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Red));
        } else if (mem.eql(u8, input, "green")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Green));
        } else if (mem.eql(u8, input, "blue")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Blue));
        } else if (mem.eql(u8, input, "orange")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Brown));
        } else if (mem.eql(u8, input, "magenta")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Magenta));
        } else if (mem.eql(u8, input, "white")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.White));
        } else if (mem.eql(u8, input, "black")) {
            screen.current_tty.?.setColor(@intFromEnum(tty.ConsoleColors.Black));
        } else {
            printf("Command not known: \"{s}\".\nInput \"help\" to get available commands.\n", .{input});
        }
    }
};
