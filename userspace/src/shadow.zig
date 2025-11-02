const std = @import("std");

pub const ShadowEntryIterator = struct {
    buff: [4096]u8 = undefined,
    reader: std.fs.File.Reader = undefined,
    fd: i32 = 0,

    pub fn init() !ShadowEntryIterator {
        const fd = try std.posix.open(
            "/etc/shadow",
            std.os.linux.O{.ACCMODE = .RDONLY},
            0o444
        );
        var it = ShadowEntryIterator{};
        it.fd = fd;
        return it;
    }

    pub fn setup(self: *ShadowEntryIterator) void {
        var file = std.fs.File{
            .handle = self.fd
        };
        self.reader = file.reader(&self.buff);
    }

    pub fn deinit(self: *ShadowEntryIterator) void {
        self.reader.file.close();
    }

    pub fn next(self: *ShadowEntryIterator) !?ShadowEntry {
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
        return try ShadowEntry.fromShadowLine(line);
    }
};

pub const ShadowEntry = struct{
    name: []const u8 = "",
    pass: []const u8 = "",

    pub fn fromShadowLine(line: []const u8) !ShadowEntry {
        var entry = ShadowEntry{};
        var it = std.mem.tokenizeScalar(u8, line[0..line.len], ':');
        if (it.next()) |name| {
            entry.name = name;
        } else {
            return error.NoNameInShadowEntry;
        }
        if (it.next()) |passwd| {
            entry.pass = passwd;
        } else {
            return error.NoPasswordInShadowEntry;
        }
        return entry;
    }
};
