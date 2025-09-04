const screen = @import("drivers").screen;
const kernel = @import("kernel");
const fmt = @import("std").fmt;
const AnyWriter = @import("std").Io.AnyWriter;


pub const writer = AnyWriter(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    // Print the string passed to the callback
    if (screen.current_tty) |t|
        t.print(string);
    return string.len;
}

var mtx = kernel.Mutex.init();

pub fn printf(comptime format: []const u8, args: anytype) void {
    if (screen.current_tty) |t| {
        var buf: [2000]u8 = undefined;
        const str = fmt.bufPrint(&buf, format, args) catch {
            return ;
        };
        mtx.lock();
        defer mtx.unlock();
        t.print(str);
    }
    // fmt.format(writer, format, args) catch unreachable;
}

pub fn printfLen(comptime format: []const u8, args: anytype) u32 {
    if (screen.current_tty) |t| {
        var buf: [2000]u8 = undefined;
        const str = fmt.bufPrint(&buf, format, args) catch {
            return 0;
        };
        mtx.lock();
        defer mtx.unlock();
        t.print(str);
        return str.len;
    }
    return 0;
    // fmt.format(writer, format, args) catch unreachable;
}