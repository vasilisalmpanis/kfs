const mem = @import("std").mem;
const debug = @import("debug");
const printf = @import("debug").printf;
const system = @import("arch").system;
const screen = @import("screen.zig");
const tty = @import("tty-fb.zig");
const krn = @import("kernel");
const std = @import("std");
const keymaps = @import("./keymaps.zig");

const ShellCommandHandler = fn (self: *Shell, args: [][]const u8) void;

const MAX_ARGS: usize = 10;

pub const ShellCommand = struct {
    name: []const u8,
    desc: []const u8,
    hndl: *const ShellCommandHandler,
};

pub const Shell = struct {
    arg_buf: [MAX_ARGS][]const u8 = undefined,
    buffer: [3000]u8 = .{0} ** 3000,
    fba: std.heap.FixedBufferAllocator = undefined,
    commands: std.StringHashMap(ShellCommand) = undefined,

    pub fn init() Shell {
        var shell = Shell{};
        shell.fba = std.heap.FixedBufferAllocator.init(&shell.buffer);
        shell.commands = std.StringHashMap(ShellCommand).init(
            shell.fba.allocator(),
        );
        shell.registerBuiltins();
        return shell;
    }

    pub fn registerCommand(
        self: *Shell,
        command: ShellCommand,
    ) void {
        self.commands.put(command.name, command) catch |err| {
            printf("Error registering command: {!}\n", .{err});
        };
    }

    fn registerBuiltins(self: *Shell) void {
        self.registerCommand(.{ .name = "help", .desc = "Display this help message", .hndl = &help });
        self.registerCommand(.{ .name = "kill", .desc = "Kill a process by PID (kill 3)", .hndl = &kill }); // FIX: killing with shell is not working. Something wrong with arguments.
        self.registerCommand(.{ .name = "ps", .desc = "Show tasks", .hndl = &ps });
        self.registerCommand(.{ .name = "pstree", .desc = "Show tasks tree", .hndl = &psTree });
        self.registerCommand(.{ .name = "stack", .desc = "Print the stack trace", .hndl = &stack });
        // self.registerCommand(.{ .name = "neofetch", .desc = "Show system info", .hndl = &neofetch });
        self.registerCommand(.{ .name = "jiffies", .desc = "Show jiffies", .hndl = &jiffies });
        self.registerCommand(.{ .name = "uptime", .desc = "Show uptime in seconds", .hndl = &uptime });
        self.registerCommand(.{ .name = "gdt", .desc = "Print GDT", .hndl = &gdt });
        self.registerCommand(.{ .name = "tss", .desc = "Print TSS", .hndl = &tss });
        self.registerCommand(.{ .name = "reboot", .desc = "Reboot the PC", .hndl = &reboot });
        self.registerCommand(.{ .name = "shutdown", .desc = "Power off the PC", .hndl = &shutdown });
        self.registerCommand(.{ .name = "halt", .desc = "Halt the PC", .hndl = &halt });
        self.registerCommand(.{ .name = "test", .desc = "Run tests", .hndl = &runTests });
        self.registerCommand(.{ .name = "color", .desc = "Change the input color (color FFAABB bg)", .hndl = &color });
        self.registerCommand(.{ .name = "mm", .desc = "Walk page tables", .hndl = &mm });
        self.registerCommand(.{ .name = "mm-usage", .desc = "Show memory usage", .hndl = &mmUsage });
        self.registerCommand(.{ .name = "sym", .desc = "Lookup symbol name by address", .hndl = &sym });
        self.registerCommand(.{ .name = "vmas", .desc = "Print task's VMAs", .hndl = &vmas });
        self.registerCommand(.{ .name = "layout", .desc = "Change keyboard layout", .hndl = &layout });
    }

    pub fn handleInput(self: *Shell, input: []const u8) void {
        if (input.len == 0) return;

        var arg_count: usize = 0;
        var it = std.mem.tokenizeAny(u8, input, " \t");
        while (it.next()) |arg| {
            if (arg_count < MAX_ARGS) {
                self.arg_buf[arg_count] = arg;
                arg_count += 1;
            }
        }
        if (arg_count == 0) return;
        
        const cmd_name = self.arg_buf[0];
        const cmd_args = self.arg_buf[1..arg_count];
        if (self.commands.get(cmd_name)) |cmd| {
            cmd.hndl(self, cmd_args);
        } else {
            printf("Command not known: \"{s}\".\nInput \"help\" to get available commands.\n", .{input});
        }
    }
};


fn help(self: *Shell, args: [][]const u8) void {
    _ = args;
    printf("available commands:\n", .{});
    var it = self.commands.iterator();
    while (it.next()) |entry| {
        printf("  {s}: {s}\n", .{entry.value_ptr.name, entry.value_ptr.desc});
    }
}

fn kill(_: *Shell, args: [][]const u8) void {
    if (args.len < 2) {
        debug.printf("Usage: kill <signal> <pid>\n", .{});
        return;
    }
    const sig: u32 = std.fmt.parseInt(u8, args[0], 10) catch 0;
    if (sig == 0 or sig >= 31) {
        debug.printf("Invalid signal: {s}\n", .{args[0]});
        return;
    }
    const pid = std.fmt.parseInt(u8, args[1], 10) catch 0;
    if (pid == 0) {
        debug.printf("Invalid PID: {s}\n", .{args[1]});
        return;
    }
    asm volatile(
        \\ mov $37, %eax
        \\ int $0x80
        :
        : [ebx] "{ebx}" (pid), [ecx] "{ecx}" (sig),
    );
}

fn ps(_: *Shell, _: [][]const u8) void {
    debug.ps();
}

fn psTree(_: *Shell, _: [][]const u8) void {
    debug.psTree();
}

fn stack(_: *Shell, _: [][]const u8) void {
    debug.traceStackTrace(20);
}

// fn neofetch(_: *Shell, _: [][]const u8) void {
//     debug.neofetch(screen.current_tty.?, krn.boot_info);
// }

fn jiffies(_: *Shell, _: [][]const u8) void {
    debug.printf("{d}\n", .{krn.jiffies.jiffies});
}

fn uptime(_: *Shell, _: [][]const u8) void {
    debug.printf("{d}\n", .{krn.getSecondsFromStart()});
}

fn gdt(_: *Shell, _: [][]const u8) void {
    debug.printGDT();
}

fn tss(_: *Shell, _: [][]const u8) void {
    debug.printTSS();
}

fn reboot(_: *Shell, _: [][]const u8) void {
    system.reboot();
}

fn shutdown(_: *Shell, _: [][]const u8) void {
    system.shutdown();
}

fn halt(_: *Shell, _: [][]const u8) void {
    system.halt();
}

fn runTests(_: *Shell, _: [][]const u8) void {
    debug.runTests();
}

fn mm(_: *Shell, _: [][]const u8) void {
    debug.walkPageTables();
}

fn mmUsage(_: *Shell, _: [][]const u8) void {
    debug.printMapped();
}

fn color(_: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        debug.printf(
            \\Usage: color <color> [bg]
            \\  Available colors: red, green, blue, orange, magenta, white, black
            \\  Or a hex value (FFAABB)
            \\  Example: color FFAABB bg
            \\
            , .{}
        );
        return;
    }
    var col: u32 = 0;
    if (mem.eql(u8, args[0], "red")) {
        col = @intFromEnum(tty.ConsoleColors.Red);
    } else if (mem.eql(u8, args[0], "green")) {
        col = @intFromEnum(tty.ConsoleColors.Green);
    } else if (mem.eql(u8, args[0], "blue")) {
        col = @intFromEnum(tty.ConsoleColors.Blue);
    } else if (mem.eql(u8, args[0], "orange")) {
        col = @intFromEnum(tty.ConsoleColors.Brown);
    } else if (mem.eql(u8, args[0], "magenta")) {
        col = @intFromEnum(tty.ConsoleColors.Magenta);
    } else if (mem.eql(u8, args[0], "white")) {
        col = @intFromEnum(tty.ConsoleColors.White);
    } else if (mem.eql(u8, args[0], "black")) {
        col = @intFromEnum(tty.ConsoleColors.Black);
    } else {
        col = std.fmt.parseInt(u32, args[0], 16) catch 0;
    }

    if (args.len > 1 and std.mem.eql(u8, args[1], "bg")) {
        screen.current_tty.?.setBgColor(col);
    } else {
        screen.current_tty.?.setColor(col);
    }
    screen.current_tty.?.reRenderAll();
}

fn sym(_: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        debug.printf(
            \\Usage: sym <address>
            \\  Example: sym c013ad50
            \\
            , .{}
        );
        return ;
    }
    const addr: u32 = std.fmt.parseInt(u32, args[0], 16) catch 0;
    debug.printf("{x}: {s}\n", .{
        addr,
        if (debug.lookupSymbol(addr)) |s| s else "?"
    });
    return;
}

fn vmas(_: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        debug.printf(
            \\Usage: vmas <task pid>
            \\  Example: vmas 3
            \\
            , .{}
        );
        return ;
    }
    const pid: u32 = std.fmt.parseInt(u32, args[0], 10) catch 0;
    debug.printTaskVMAs(pid);
    return;
}

fn layout(_: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        debug.printf(
            \\Usage: layout <language>
            \\  Available languages: us, de
            \\  Example: layout de
            \\
            , .{}
        );
        return ;
    }
    if (std.mem.eql(u8, args[0], "us")) {
        krn.keyboard.setKeymap(&keymaps.keymap_us);
    }
    else if (std.mem.eql(u8, args[0], "de")) {
        krn.keyboard.setKeymap(&keymaps.keymap_de);
    }
    else {
        debug.printf("Unknown layout!\n", .{});
    }
    return;
}
