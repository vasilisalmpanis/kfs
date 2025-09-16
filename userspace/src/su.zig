const std = @import("std");
const Shell = @import("./shell.zig").Shell;
const shadow = @import("shadow.zig");
const passwd = @import("passwd.zig");

fn changeIdentity(uid: u32, gid: u32) !bool {
    try std.posix.setgid(gid);
    try std.posix.setuid(uid);
    return true;
}

fn checkPassword(_: *Shell, username: []const u8, password: []const u8) !bool{
    var s_it = try shadow.ShadowEntryIterator.init();
    s_it.setup();
    while (try s_it.next()) |entry| {
        if (std.mem.eql(u8, username, entry.name)) {
            var buffer: [16]u8 = .{0} ** 16;
            var hex: [32]u8 = .{0} ** 32;
            std.crypto.hash.Md5.hash(password, &buffer, .{});
            for (buffer, 0..) |b, i| {
                _ = try std.fmt.bufPrint(hex[i * 2 ..], "{x:0>2}", .{b});
            }
            if (entry.pass.len != 32)
                return false;
            if (std.mem.eql(u8, hex[0..32], entry.pass)) {
                return true;
            }
            return false;
        }
    }
    return error.NotFound;
}

fn suParsePasswdLine(self: *Shell, username: []const u8, line: []const u8) !bool {
    const p_entry: passwd.PasswdEntry = try passwd.PasswdEntry.fromPasswdLine(line);
    if (!std.mem.eql(u8, p_entry.name, username)) return false;
    var password: [128]u8 = .{0} ** 128;
    self.print("Password: ", .{});
    const pass_len = self.stdout.file.read(password[0..128]) catch |err| {
        self.print("Error: {t}\n", .{err});
        return err;
    };
    if (try checkPassword(self, p_entry.name, password[0..pass_len - 1])) {
        return try changeIdentity(p_entry.uid, p_entry.gid);
    }
    return false;
}

pub fn su(self: *Shell, args: [][]const u8) void {
    const pid = std.posix.fork() catch {
        return ;
    };
    if (pid == 0) {
        self.running += 1;
        do_su(self, args) catch {
            std.posix.exit(0);
        };
        return ;
    }
    _ = std.posix.wait4(pid, 0, null);
}

pub fn do_su(self: *Shell, args: [][]const u8) !void {
    var username: []const u8 = "root";
    if (args.len > 0) {
        username = args[0];
    }
    const passwd_file = std.posix.open(
        "/etc/passwd",
        std.os.linux.O{.ACCMODE = .RDONLY},
        0o444
    ) catch |err| {
        self.print("cat: cannot open /etc/passwd: {t}\n", .{err});
        return ;
    };
    defer std.posix.close(passwd_file);
    var lines_buf: [2048]u8 = .{0} ** 2048;
    var lines_pos: usize = 0;
    var buff: [512]u8 = .{0} ** 512;
    const buff_s: []u8 = buff[0..512];
    outer: while (true) {
        const len = std.posix.read(passwd_file, buff_s) catch |err| {
            self.print("error reading: {t}\n", .{err});
            return err;
        };
        if (len == 0) break;
        if (len + lines_pos > 2048) {
            self.print("/etc/passwd: corrupted\n", .{});
            return error.Corrupted;
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
                return err;
            }) return;
        }
        return error.NoUser;
    }
}
