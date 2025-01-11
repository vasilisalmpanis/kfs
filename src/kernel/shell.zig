const mem = @import("std").mem;
const debug = @import("debug.zig");
const system = @import("arch").system;
const printf = @import("printf.zig").printf;

pub const Shell = struct {
    buf: [100]u8,
    pos: u16,
    
    pub fn init() *Shell {
        var shell = Shell{
            .buf = .{0} ** 100,
            .pos = 0,
        };
        return &shell;
    }

    fn exec(self: *Shell) void {
        if (mem.eql(u8, self.buf[0..4], "help")) {
            self.clear_buf();
            printf("available commands:\n\tstack: show stack trace\n\treboot: reboot pc\n\thelp: show this message\n", .{});
            return;
        }
        if (mem.eql(u8, self.buf[0..5], "stack")) {
            self.clear_buf();
            debug.TraceStackTrace(10);
            return;
        }
        if (mem.eql(u8, self.buf[0..6], "reboot")) {
            self.clear_buf();
            system.reboot();
            return;
        }
    }

    fn clear_buf(self: *Shell) void {
        @memset(self.buf[0..100], 0);
        self.pos = 0;
    }

    pub fn handleInput(self: *Shell, input: []const u8) void {
        for (input) |c| {
            self.buf[self.pos] = c;
            self.pos += 1;
            if (c == '\n' or self.pos == 99) {
                self.exec();
                self.clear_buf();
            }
        }
    }
};
