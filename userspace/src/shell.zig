const std = @import("std");
const su = @import("./su.zig").su;

const ShellCommandHandler = fn (self: *Shell, args: [][]const u8) void;

const MAX_ARGS: usize = 10;

pub const ShellCommand = struct {
    name: []const u8,
    desc: []const u8,
    hndl: *const ShellCommandHandler,
};

pub const Shell = struct {
    stdout: std.fs.File.Writer = undefined,
    stdout_buff: [1024]u8 = undefined,
    arg_buf: [MAX_ARGS][]const u8 = undefined,
    commands: std.StringHashMap(ShellCommand) = undefined,

    pub fn init(stdout: usize) Shell {
        var file = std.fs.File{
            .handle = @intCast(stdout),
        };
        var shell = Shell{
            .stdout_buff = .{0} ** 1024,
        };
        shell.stdout = file.writer(&shell.stdout_buff);

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        shell.commands = std.StringHashMap(ShellCommand).init(
            arena.allocator(),
        );
        shell.registerBuiltins();
        return shell;
    }

    pub fn print(self: *Shell, comptime fmt: []const u8, args: anytype) void {
        const _stdout = &self.stdout.interface;
        _stdout.print(fmt, args) catch |err| {
            std.debug.print("Shell print error: {t}\n", .{err});
        };
        _stdout.flush() catch |err| {
            std.debug.print("Shell flush error: {t}\n", .{err});
        };
    }

    pub fn registerCommand(
        self: *Shell,
        command: ShellCommand,
    ) void {
        self.commands.put(command.name, command) catch |err| {
            self.print("Error registering command: {any}\n", .{err});
        };
    }

    fn registerBuiltins(self: *Shell) void {
        self.registerCommand(.{ .name = "help", .desc = "Display this help message", .hndl = &help });
        self.registerCommand(.{ .name = "mount", .desc = "Mount filesystem", .hndl = &mount });
        self.registerCommand(.{ .name = "umount", .desc = "Unmount", .hndl = &umount });
        self.registerCommand(.{ .name = "ls", .desc = "List directory content", .hndl = &ls });
        self.registerCommand(.{ .name = "mkdir", .desc = "Create a new directory", .hndl = &mkdir });
        self.registerCommand(.{ .name = "cd", .desc = "Change pwd", .hndl = &cd });
        self.registerCommand(.{ .name = "cat", .desc = "Output file content", .hndl = &cat });
        self.registerCommand(.{ .name = "echo", .desc = "Output text", .hndl = &echo });
        self.registerCommand(.{ .name = "pwd", .desc = "Current working directory", .hndl = &pwd });
        self.registerCommand(.{ .name = "su", .desc = "Change user", .hndl = &su });
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
            self.print("Command not known: \"{s}\".\nInput \"help\" to get available commands.\n", .{input});
        }
    }
};


fn help(self: *Shell, args: [][]const u8) void {
    _ = args;
    self.print("available commands:\n", .{});
    var it = self.commands.iterator();
    while (it.next()) |entry| {
        self.print("  {s}: {s}\n", .{entry.value_ptr.name, entry.value_ptr.desc});
    }
}

fn kill(self: *Shell, args: [][]const u8) void {
    if (args.len < 2) {
        self.print("Usage: kill <signal> <pid>\n", .{});
        return;
    }
    const sig: u32 = std.fmt.parseInt(u8, args[0], 10) catch 0;
    if (sig == 0 or sig >= 31) {
        self.print("Invalid signal: {s}\n", .{args[0]});
        return;
    }
    const pid = std.fmt.parseInt(u8, args[1], 10) catch 0;
    if (pid == 0) {
        self.print("Invalid PID: {s}\n", .{args[1]});
        return;
    }
    asm volatile(
        \\ mov $37, %eax
        \\ int $0x80
        :
        : [ebx] "{ebx}" (pid), [ecx] "{ecx}" (sig),
    );
}

fn mount(self: *Shell, args: [][]const u8) void {
    if (args.len < 3) {
        self.print(
            \\Usage: mount source target type
            \\  Example: mount PLACEHOLDER /home/user examplefs
            \\
            , .{}
        );
        return ;
    }
    var source_buff: [256]u8 = .{0} ** 256;
    @memcpy(source_buff[0..], args[0]);
    source_buff[args[0].len] = 0;
    const source: [*:0]u8 = @ptrCast(&source_buff);

    var target_buff: [256]u8 = .{0} ** 256;
    @memcpy(target_buff[0..], args[1]);
    target_buff[args[1].len] = 0;
    const target: [*:0]u8 = @ptrCast(&target_buff);

    var fstype_buff: [256]u8 = .{0} ** 256;
    @memcpy(fstype_buff[0..], args[2]);
    fstype_buff[args[2].len] = 0;
    const fstype: [*:0]u8 = @ptrCast(&fstype_buff);

    _ = std.os.linux.mount(source, target, fstype, 0o666, 0);
}

fn umount(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: umount target
            \\  Example: umount /home/user
            \\
            , .{}
        );
        return ;
    }
}

const Dirent = extern struct{
    ino: u32,
    off: u32,
    reclen: u16,
    type: u8,
    
    pub fn getName(self: *Dirent) []const u8 {
        const name_offset: u32 = @intFromPtr(self) + @sizeOf(Dirent);
        return std.mem.span(@as([*:0]u8, @ptrFromInt(name_offset)))[0..self.reclen - @sizeOf(Dirent)];
    }

    pub fn verboseType(self: *Dirent) u8 {
        switch (self.type) {
            std.os.linux.DT.REG => return 'r',
            std.os.linux.DT.DIR => return 'd',
            std.os.linux.DT.LNK => return 'l',
            std.os.linux.DT.CHR => return 'c',
            std.os.linux.DT.BLK => return 'b',
            std.os.linux.DT.FIFO => return 'f',
            std.os.linux.DT.SOCK => return 's',
            else => {}
        }
        return 'u';
    }
};

fn ls(self: *Shell, args: [][]const u8) void {
    var l_opt = false;
    var path: []const u8 = ".";
    if (args.len > 0) {
        if (std.mem.eql(u8, args[0], "-l")) {
            l_opt = true;
            if (args.len > 1)
                path = args[1];
        } else {
            path = args[0];
        }
    }
    const fd = std.posix.open(
        path,
        std.os.linux.O{.ACCMODE = .RDONLY},
        0o444
    ) catch |err| {
        self.print("ls: cannot access '{s}': {t}\n", .{path, err});
        return ;
    };
    defer std.posix.close(fd);

    var dirp: [1024]u8 = .{0} ** 1024;
    const len = std.os.linux.getdents64(fd, &dirp, 1024);
    if (len < 0) {
        self.print("ls: getdents64 error on fd {d}\n", .{fd});
        return ;
    }
    var pos: u32 = 0;
    while (pos < len) {
        const dirent: *Dirent = @ptrFromInt(@intFromPtr(&dirp) + pos);
        if (l_opt) {
            self.print(
                "{c} {d:0>4} {s}\n", 
                .{dirent.verboseType(), dirent.ino, dirent.getName()}
            );
        } else {
            self.print("{s}\n", .{dirent.getName()});
        }
        pos += dirent.reclen;
    }
}

fn mkdir(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: mkdir <name>
            \\  Example: mkdir test
            \\
            , .{}
        );
        return ;
    }
    std.posix.mkdir(args[0], 0o777) catch |err| {
        self.print("mkdir: cannot create directory '{s}': {t}\n", .{args[0], err});
        return ;
    };
}

fn cd(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: cd <path>
            \\  Example: cd /
            \\
            , .{}
        );
        return ;
    }
    std.posix.chdir(args[0]) catch |err| {
        self.print("Error: {t}\n", .{err});
    };
}

fn cat(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: cat <path>
            \\  Example: cat /ext2/test
            \\
            , .{}
        );
        return ;
    }
    const fd = std.posix.open(
        args[0],
        std.os.linux.O{.ACCMODE = .RDONLY},
        0o444
    ) catch |err| {
        self.print("cat: cannot open '{s}': {t}\n", .{args[0], err});
        return ;
    };
    defer std.posix.close(fd);
    var buff: [1024]u8 = .{0} ** 1024;
    var buff_slice = buff[0..1024];
    while (true) {
        const res = std.posix.read(fd, buff_slice) catch |err| {
            self.print("cat: read error on '{s}': {t}\n", .{args[0], err});
            return ; 
        };
        if (res == 0) {
            break;
        } else {
            self.print("{s}", .{buff_slice[0..res]});
        }
    }
}

fn pwd(self: *Shell, _: [][]const u8) void {
    var buff: [512]u8 = .{0} ** 512;
    const res = std.posix.getcwd(buff[0..512]) catch |err| {
        self.print("error: {t}\n", .{err});
        return ;
    };
    self.print("{s}\n", .{res});
}

fn echo(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: echo <text> [file]
            \\  Example: echo hello /dev/8250 
            \\
            , .{}
        );
        return ;
    }
}
