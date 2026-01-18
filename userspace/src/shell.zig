const std = @import("std");
const su = @import("./su.zig").su;
const passwd = @import("./passwd.zig");

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
    line_buff: [4096]u8 = undefined,
    arg_buf: [MAX_ARGS][]const u8 = undefined,
    commands: std.StringHashMap(ShellCommand) = undefined,
    running: u32 = 0,

    pub fn init() Shell {
        var file = std.fs.File.stdout();
        var shell = Shell{
            .stdout_buff = .{0} ** 1024,
            .running = 1,
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
        self.registerCommand(.{ .name = "k", .desc = "Kernelspace command", .hndl = &kshell });
        self.registerCommand(.{ .name = "creds", .desc = "Print user credentials", .hndl = &creds });
        self.registerCommand(.{ .name = "stat", .desc = "Stat file", .hndl = &stat });
        self.registerCommand(.{ .name = "exit", .desc = "Exit", .hndl = &exit });
        self.registerCommand(.{ .name = "whoami", .desc = "Who am I?", .hndl = &whoami });
        self.registerCommand(.{ .name = "users", .desc = "Print users", .hndl = &users });
        self.registerCommand(.{ .name = "env", .desc = "Print environment variables", .hndl = &env });
        self.registerCommand(.{ .name = "touch", .desc = "Create new file", .hndl = &touch });
        self.registerCommand(.{ .name = "execve", .desc = "Execute a program", .hndl = &execve });
        self.registerCommand(.{ .name = "kill", .desc = "Send signal", .hndl = &kill });
        self.registerCommand(.{ .name = "insmod", .desc = "load module", .hndl = &insmod });
        self.registerCommand(.{ .name = "rmmod", .desc = "unload module", .hndl = &rmmod });
        self.registerCommand(.{ .name = "access", .desc = "access syscall", .hndl = &access });
    }

    pub fn handleInput(self: *Shell, input: []const u8) void {
        if (input.len == 0) return;

        @memcpy(self.line_buff[0..input.len], input);
        const _line: []const u8 = self.line_buff[0..input.len];
        var arg_count: usize = 0;
        var it = std.mem.tokenizeAny(u8, _line, " \t\r\n");
        while (it.next()) |arg| {
            if (arg_count < MAX_ARGS) {
                self.arg_buf[arg_count] = arg;
                arg_count += 1;
            }
        }
        if (arg_count == 0) return;
        
        const cmd_name = self.arg_buf[0];
        const cmd_args = self.arg_buf[1..arg_count];
        self.print("\n", .{});
        if (self.commands.get(cmd_name)) |cmd| {
            cmd.hndl(self, cmd_args);
        } else {
            if (cmd_name.len > 0 and cmd_name[0] == '/') {
                execve(self, self.arg_buf[0..arg_count]);
            } else if (cmd_name.len > 0) {
                var full_cmd: [512]u8 = .{0} ** 512;
                @memcpy(full_cmd[0..5], "/bin/");
                @memcpy(full_cmd[5..], cmd_name);
                self.arg_buf[0] = full_cmd[0..cmd_name.len + 5];
                execve(self, self.arg_buf[0..arg_count]);
            } else {
                self.print("Command not known: \"{s}\".\nInput \"help\" to get available commands.\n", .{cmd_name});
            }
        }
    }

    pub fn start(self: *Shell) void {
        var len: u32 = 0;
        var input: [4096]u8 = .{0} ** 4096;
        while (self.running > 0) {
            self.print("> ", .{});
            len = std.os.linux.read(0, &input, 4096);
            if (len > 0) {
                self.handleInput(input[0..len]);
            }
        }
        while (true) {}
    }
};

fn exit(self: *Shell, _: [][]const u8) void {
    if (self.running > 1) {
        std.os.linux.exit(0);
    } else {
        self.running = 0;
    }
}

fn stat(self: *Shell, args: [][]const u8) void {
    if (args.len != 1) {
            self.print("Provide path argument\n", .{});
            return ;
    }
    var temp: std.os.linux.Stat = undefined;
    var buffer: [100]u8 = .{0} ** 100;
    @memcpy(buffer[0..args[0].len], args[0]);
    buffer[args[0].len] = 0;
    if (std.os.linux.stat(@ptrCast(&buffer), &temp) == 0) {
        self.print("Stat: {any}\n", .{temp});
    } else {
        self.print("Stat failed\n", .{});
    }
}

fn creds(self: *Shell, _: [][]const u8) void {
    const uid = std.os.linux.getuid();
    const gid = std.os.linux.getgid();
    self.print("User's uid {d} gid {d}\n", .{uid, gid});
}

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
    _ = std.posix.kill(@intCast(pid), @intCast(sig)) catch |err| {
        self.print("Kill error {t}\n", .{err});
    };
    // asm volatile(
    //     \\ mov $37, %eax
    //     \\ int $0x80
    //     :
    //     : [ebx] "{ebx}" (pid), [ecx] "{ecx}" (sig),
    // );
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

    const res: u32 = std.os.linux.mount(source, target, fstype, 0o666, 0);
    if (res != 0) {
        self.print("mount: {s}: must be superuser to use mount.\n",.{args[1]});
    }
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
    var target_buff: [256]u8 = .{0} ** 256;
    @memcpy(target_buff[0..], args[0]);
    target_buff[args[0].len] = 0;
    const target: [*:0]u8 = @ptrCast(&target_buff);

    const res: u32 = std.os.linux.umount(target);
    if (res != 0) {
        self.print("error: umount: {d}\n",.{res});
    }
}

const Dirent = extern struct{
    ino: u64,
    off: i64,
    reclen: u16,
    type: u8,
    
    pub fn getName(self: *Dirent) []const u8 {
        const name_offset: u32 = @intFromPtr(self) + @sizeOf(Dirent) - 1;
        return std.mem.span(@as([*:0]u8, @ptrFromInt(name_offset)))[0..self.reclen - @sizeOf(Dirent)];
    }

    pub fn verboseType(self: *Dirent) u8 {
        switch (self.type) {
            std.os.linux.DT.REG => return '-',
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

const Mode = packed struct {
    other_x: bool = false,
    other_w: bool = false,
    other_r: bool = false,
    grp_x: bool = false,
    grp_w: bool = false,
    grp_r: bool = false,
    usr_x: bool = false,
    usr_w: bool = false,
    usr_r: bool = false,
    type: u7 = 0,
};

fn verboseMode(res: *[9]u8, mode: u32) void {
    const _mode: Mode = @bitCast(@as(u16, @truncate(mode)));
    res[0] = if (_mode.usr_r) 'r' else '-';
    res[1] = if (_mode.usr_w) 'w' else '-';
    res[2] = if (_mode.usr_x) 'x' else '-';
    res[3] = if (_mode.grp_r) 'r' else '-';
    res[4] = if (_mode.grp_w) 'w' else '-';
    res[5] = if (_mode.grp_x) 'x' else '-';
    res[6] = if (_mode.other_r) 'r' else '-';
    res[7] = if (_mode.other_w) 'w' else '-';
    res[8] = if (_mode.other_x) 'x' else '-';
}

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

    var stat_buf: std.os.linux.Stat = undefined;
    var buffer: [64]u8 = .{0} ** 64;
    @memcpy(buffer[0..path.len], path);
    buffer[path.len] = 0;
    _ = std.os.linux.stat(@ptrCast(&buffer), &stat_buf);
    if (stat_buf.mode & std.os.linux.S.IFMT != std.os.linux.S.IFDIR) {
        self.print("{s}\n", .{path});
        return ;
    }
    var dirp: [1024]u8 = .{0} ** 1024;
    const len = std.os.linux.getdents64(fd, &dirp, 1024);
    if (len > 1024) {
        self.print("ls: getdents64 error on fd {d}\n", .{fd});
        return ;
    }
    var pos: u32 = 0;
    while (pos < len) {
        const dirent: *Dirent = @ptrFromInt(@intFromPtr(&dirp) + pos);
        const name = dirent.getName();
        if (l_opt) {
            const curr_stat = std.posix.fstatat(fd, name, 0) catch {
                self.print(
                    "{c}????????? ? ? ? ?            ? {s}\n",
                    .{dirent.verboseType(), name}
                );
                pos += dirent.reclen;
                continue ;
            };
            var perms: [9]u8 = .{0} ** 9;
            verboseMode(&perms, curr_stat.mode);

            const epoch_secs = std.time.epoch.EpochSeconds{
                .secs = @intCast(curr_stat.mtim.sec)
            };
            const epoch_day = epoch_secs.getEpochDay();
            const epoch_year = epoch_day.calculateYearDay();
            const epoch_month_day = epoch_year.calculateMonthDay();
            const epoch_day_sec = epoch_secs.getDaySeconds();
            self.print(
                "{c}{s} {d:>6} {d:>6} {Bi:>7.0} {d:>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}  {s}\n", 
                .{
                    dirent.verboseType(),
                    perms[0..9],
                    curr_stat.uid,
                    curr_stat.gid,
                    @as(u64, @intCast(curr_stat.size)),
                    epoch_year.year,
                    epoch_month_day.month,
                    epoch_month_day.day_index + 1,
                    epoch_day_sec.getHoursIntoDay(),
                    epoch_day_sec.getMinutesIntoHour(),
                    name
                }
            );
        } else {
            self.print("{s}\n", .{name});
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
    var buff: [4096]u8 = .{0} ** 4096;
    var buff_slice = buff[0..4096];
    while (true) {
        const res = std.posix.read(fd, buff_slice) catch |err| {
            self.print("cat: read error on '{s}': {t}\n", .{args[0], err});
            return ; 
        };
        if (res == 0) {
            break;
        } else {
            if (!std.mem.allEqual(u8, buff_slice[0..res], 0))
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
    if (args.len < 2) {
        self.print("{s}\n", .{args[0]});
        return ;
    }
    const fd = std.posix.open(
        args[1],
        std.os.linux.O{
            .ACCMODE = .WRONLY,
            .APPEND = true,
            .CREAT = true
        },
        0x666
    ) catch |err| {
        self.print("Error: {t}\n", .{err});
        return ;
    };
    _ = std.posix.write(fd, args[0]) catch |err| {
        self.print("Error: {t}\n", .{err});
    };
    std.posix.close(fd);
}

fn kshell(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: k <command> <args>
            \\  Example: k ps
            \\
            , .{}
        );
        return ;
    }
    const sys = std.os.linux.SYS.landlock_create_ruleset;
    const k_args = args[0..];
    _ = std.os.linux.syscall1(sys, @intFromPtr(&k_args));
}

fn whoami(self: *Shell, _: [][]const u8) void {
    const uid = std.posix.getuid();
    const pass = passwd.PasswdEntry.findByUID(uid) catch |err| {
        self.print("error: {t}\n", .{err});
        return ;
    };
    if (pass == null) {
        self.print("Not found /etc/passwd entry for uid {d}\n", .{uid});
        return;
    }
    self.print(
        \\  user:   {s}
        \\  uid:    {d}
        \\  gid:    {d}
        \\  groups: {s}
        \\  home:   {s}
        \\  shell:  {s}
        \\
        , .{
            pass.?.name,
            pass.?.uid,
            pass.?.gid,
            pass.?.groups,
            pass.?.home,
            pass.?.shell,
        }
    );
}

fn users(self: *Shell, _: [][]const u8) void {
    var it = passwd.PasswdEntry.iterator() catch |err| {
        self.print("error: {t}\n", .{err});
        return ;
    };
    defer it.deinit();
    while (it.next() catch |err| {
        self.print("error: {t}\n", .{err});
        return;
    }) |entry| {
        self.print(" {s:<20} {d:>6} {d:>6}\n", .{
            entry.name,
            entry.uid,
            entry.gid,
        });
    }
}


fn env(self: *Shell, _: [][]const u8) void {
    for (std.os.environ) |entry| {
        self.print("{s}\n", .{entry});
    }
}

fn touch(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: touch <name>
            \\  Example: touch new_file 
            \\
            , .{}
        );
        return ;
    }
    _ = std.posix.open(
        args[0],
        std.os.linux.O{ .ACCMODE = .RDWR, .CREAT = true },
        0o666
    ) catch |err| {
        self.print("Error: {t}\n", .{err});
    };
}

fn execve(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: execve cmd <args>
            \\  Example: execve /bin/ls -l /
            \\
            , .{}
        );
        return ;
    }
    const pid = std.posix.fork() catch |err | {
        self.print("fork error {t}\n", .{err});
        return ;
    };
    if (pid == 0) {
        var buffer: [2048]u8 = .{0} ** 2048;
        var alloc = std.heap.FixedBufferAllocator.init(&buffer);
        std.process.execv(alloc.allocator(), args) catch {
            self.print("execve error\n", .{});
            std.posix.exit(0);
            return ;
        };
    }
    const res = std.posix.waitpid(pid, 0);
    if (res.status != 0) {
        if (std.os.linux.W.IFSIGNALED(res.status))
            std.debug.print("Killed\n", .{});
    }
}

fn insmod(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: insmod module
            \\  Example: ismod /modules/keyboard.o
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
        self.print("ls: cannot access '{s}': {t}\n", .{args[0], err});
        return ;
    };
    defer std.posix.close(fd);
    _ = std.os.linux.syscall1(std.os.linux.syscalls.X86.finit_module, @intCast(fd));
}

fn rmmod(self: *Shell, args: [][]const u8) void {
    if (args.len < 1) {
        self.print(
            \\Usage: rmmod <module name>
            \\  Example: rmmod keyboard.o
            \\
            , .{}
        );
        return ;
    }
    var name_buf: [256] u8 = .{0} ** 256;
    @memcpy(name_buf[0..args[0].len], args[0][0..]);
    name_buf[args[0].len] = 0;
    const res = std.os.linux.syscall1(
        std.os.linux.syscalls.X86.delete_module,
        @intFromPtr(&name_buf)
    );
    if (res == 0) {
        self.print("module unloaded\n", .{});
    } else {
        self.print("error unloading: {t}\n", .{std.posix.errno(res)});
    }
}

fn access(self: *Shell, args: [][]const u8) void {
    if (args.len < 2) {
        self.print(
            \\Usage: access <path> <mode>
            \\  Example: access . F_OK
            \\
            , .{}
        );
        return;
    }
    var mode: u32 = std.posix.F_OK;
    if (std.mem.eql(u8,args[1],"F_OK")) {
        mode = std.posix.F_OK;
    } else if (std.mem.eql(u8,args[1],"W_OK")) {
        mode = std.posix.W_OK;
    } else if (std.mem.eql(u8,args[1],"X_OK")) {
        mode = std.posix.X_OK;
    }else if (std.mem.eql(u8,args[1],"R_OK")) {
        mode = std.posix.R_OK;
    } else {
        self.print("Wrong mode {s}\n", .{args[1]});
        return ;
    }
    _ = std.posix.access(args[0], mode) catch |err| {
        self.print("Access {s} {s}: {any}\n", .{args[0], args[1], err});
        return ;
    };
    self.print("Access result for {s} {s}: {d}\n", .{args[0], args[1], 0});
    return ;
}
