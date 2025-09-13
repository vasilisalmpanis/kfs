const std = @import("std");
const Shell = @import("./shell.zig").Shell;

fn changeIdentity(uid: []const u8, gid: []const u8) !bool {
    const _uid = try std.fmt.parseInt(u32, uid, 10);
    const _gid = try std.fmt.parseInt(u32, gid, 10);
    try std.posix.setgid(_gid);
    try std.posix.setuid(_uid);
    return true;
}

fn suParsePasswdLine(self: *Shell, username: []const u8, line: []const u8) !bool {
    var it = std.mem.tokenizeScalar(u8, line, ':');
    if (it.next()) |psw_username| {
        if (std.mem.eql(u8, psw_username, username)) {
            if (it.next()) |psw_pass| {
                var password: [128]u8 = .{0} ** 128;
                self.print("Password: ", .{});
                const pass_len = self.stdout.file.read(password[0..128]) catch |err| {
                    self.print("Error: {t}\n", .{err});
                    return err;
                };
                if (std.mem.eql(u8, psw_pass, password[0..pass_len - 1])) {
                    if (it.next()) |uid_s| {
                        if (it.next()) |guid_s| {
                            return try changeIdentity(uid_s, guid_s);
                        } else {
                            return error.Corrupted;
                        }
                    } else {
                        return error.Corrupted;
                    }
                } else {
                    self.print("Wrong password!\n", .{});
                    return error.Access;
                }
            }
            return error.Corrupted;
        } else {
            return false;
        }
    }
    return error.Corrupted;
}

pub fn su(self: *Shell, args: [][]const u8) void {
    const pid = std.posix.fork() catch {
        return ;
    };
    if (pid == 0) {
        self.running += 1;
        do_su(self, args);
        return ;
    }
    _ = std.posix.wait4(pid, 0, null);
}

pub fn do_su(self: *Shell, args: [][]const u8) void {
    var username: []const u8 = "root";
    if (args.len > 0) {
        username = args[0];
    }
    const passwd = std.posix.open(
        "/etc/passwd",
        std.os.linux.O{.ACCMODE = .RDONLY},
        0o444
    ) catch |err| {
        self.print("cat: cannot open /etc/passwd: {t}\n", .{err});
        return ;
    };
    defer std.posix.close(passwd);
    var lines_buf: [2048]u8 = .{0} ** 2048;
    var lines_pos: usize = 0;
    var buff: [512]u8 = .{0} ** 512;
    const buff_s: []u8 = buff[0..512];
    outer: while (true) {
        const len = std.posix.read(passwd, buff_s) catch |err| {
            self.print("error reading: {t}\n", .{err});
            return ;
        };
        if (len == 0) break;
        if (len + lines_pos > 2048) {
            self.print("/etc/passwd: corrupted\n", .{});
            return ;
        }
        @memcpy(lines_buf[lines_pos..lines_pos+len], buff_s[0..len]);
        lines_pos += len;
        if (!std.mem.containsAtLeastScalar(
            u8,
            lines_buf[0..lines_pos],
            1,
            '\n'
        )) {
            continue;
        }
        var it = std.mem.tokenizeScalar(u8, lines_buf[0..lines_pos], '\n');
        while (it.next()) |line| {
            if (it.rest().len == 0 and line.ptr[line.len] != '\n') {
                lines_pos = line.len;
                @memcpy(lines_buf[0..lines_pos], line[0..lines_pos]);
                continue :outer;
            }
            if (suParsePasswdLine(self, username, line) catch |err| {
                self.print("Error: {t}\n", .{err});
                return ;
            }) {
                return;
            }   
        }
    }
}
