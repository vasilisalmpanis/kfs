const mem = @import("std").mem;
const debug = @import("debug");
const printf = @import("debug").printf;
const system = @import("arch").system;
const screen = @import("screen.zig");
const tty = @import("tty-fb.zig");
const krn = @import("kernel");

pub const Shell = struct {
    pub fn init() *Shell {
        var shell = Shell{};
        return &shell;
    }

    pub fn handleInput(self: *Shell, input: []const u8) void {
        _ = self;
        if (mem.eql(u8, input, "help")) {
            printf(
                \\
                \\available commands:
                \\  stack: Print the stack trace
                \\  reboot: Reboot the PC
                \\  shutdown: Power off the PC
                \\  halt: Halt the PC
                \\  uptime: Show uptime in seconds
                \\  ps: Show tasks
                \\  neofetch: Show system info
                \\  [color name]: Change the input color
                \\  help: Display this help message
                \\
            , .{});
        } else if (mem.eql(u8, input, "stack")) {
            debug.traceStackTrace(10);
        } else if (mem.eql(u8, input, "neofetch")) {
            debug.neofetch(screen.current_tty.?, krn.boot_info);
        } else if (mem.eql(u8, input, "ps")) {
            debug.ps();
        } else if (mem.eql(u8, input, "pstree")) {
            debug.psTree(&krn.task.initial_task, 0, false);
        } else if (mem.eql(u8, input, "jiffies")) {
            debug.printf("{d}\n", .{krn.jiffies.jiffies});
        } else if (mem.eql(u8, input, "uptime")) {
            debug.printf("{d}\n", .{krn.getSecondsFromStart()});
        } else if (mem.eql(u8, input, "gdt")) {
            debug.printGDT();
        } else if (mem.eql(u8, input, "tss")) {
            debug.printTSS();
        } else if (mem.eql(u8, input, "reboot")) {
            system.reboot();
        } else if (mem.eql(u8, input, "shutdown")) {
            system.shutdown();
        } else if (mem.eql(u8, input, "halt")) {
            system.halt();
        } else if (mem.eql(u8, input, "test")) {
            debug.runTests();
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
