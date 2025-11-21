const std = @import("std");

pub const PasswdEntryIterator = struct {
    buff: [4096]u8 = undefined,
    reader: std.fs.File.Reader = undefined,

    pub fn init() !PasswdEntryIterator {
        const fd = try std.posix.open(
            "/etc/passwd",
            std.os.linux.O{.ACCMODE = .RDONLY},
            0o444
        );
        var file = std.fs.File{
            .handle = fd
        };

        var it = PasswdEntryIterator{};
        it.reader = file.reader(&it.buff);
        return it;
    }

    pub fn deinit(self: *PasswdEntryIterator) void {
        self.reader.file.close();
    }

    pub fn next(self: *PasswdEntryIterator) !?PasswdEntry {
        var r = &self.reader.interface;
        const line = r.takeDelimiterExclusive('\n') catch |err| {
            switch (err) {
                error.EndOfStream => return null,
                else => return err,
            }
            return err;
        };
        if (line.len == 0) {
            return null;
        }
        r.seek += 1;
        return try PasswdEntry.fromPasswdLine(line);
    }
};

pub const PasswdEntry = struct{
    name: []const u8 = "",
    pass: []const u8 = "",
    uid: u32 = 0,
    gid: u32 = 0,
    groups: []const u8 = "",
    home: []const u8 = "",
    shell: []const u8 = "",

    pub fn findByName(name: []const u8) !?PasswdEntry {
        var it = try PasswdEntry.iterator();
        defer it.deinit();
        while (try it.next()) |entry| {
            if (std.mem.eql(u8, name, entry.name)) {
                return entry;
            }
        }
        return null;
    }

    pub fn findByUID(uid: u32) !?PasswdEntry {
        var it = try PasswdEntry.iterator();
        defer it.deinit();
        while (try it.next()) |entry| {
            if (uid == entry.uid) {
                return entry;
            }
        }
        return null;
    }

    pub fn iterator() !PasswdEntryIterator {
        return try PasswdEntryIterator.init();
    }

    pub fn fromPasswdLine(line: []const u8) !PasswdEntry {
        var entry = PasswdEntry{};
        var it = std.mem.splitScalar(u8, line, ':');
        if (it.next()) |name| {
            entry.name = name;
        } else {
            return error.NoNameInPasswdEntry;
        }
        if (it.next()) |passwd| {
            entry.pass = passwd;
        } else {
            return error.NoPasswordInPasswdEntry;
        }
        if (it.next()) |uid| {
            entry.uid = try std.fmt.parseInt(u32, uid, 10);
        } else {
            return error.NoUIDInPasswdEntry;
        }
        if (it.next()) |gid| {
            entry.gid = try std.fmt.parseInt(u32, gid, 10);
        } else {
            return error.NoUIDInPasswdEntry;
        }
        if (it.next()) |groups| {
            entry.groups = groups;
        } else {
            return error.NoGroupsInPasswdEntry;
        }
        if (it.next()) |home| {
            entry.home = home;
        } else {
            return error.NoHomeDirInPasswdEntry;
        }
        if (it.next()) |shell| {
            entry.shell = shell;
        } else {
            return error.NoShellInPasswdEntry;
        }
        return entry;
    }
};
