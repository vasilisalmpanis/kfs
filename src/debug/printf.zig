const screen = @import("drivers").screen;
const kernel = @import("kernel");
const fmt = @import("std").fmt;
const AnyWriter = @import("std").Io.AnyWriter;
const TTY = @import("drivers").platform.TTY;


pub const writer = AnyWriter(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    // Print the string passed to the callback
    if (screen.current_tty) |t|
        t.print(string);
    return string.len;
}

var mtx = kernel.Mutex.init();

pub fn print(t: *TTY, buffer: []const u8) void {
    mtx.lock();
    defer mtx.unlock();
    t.print(buffer);
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    if (screen.current_tty) |t| {
        const str = fmt.allocPrint(
            kernel.mm.kernel_allocator.allocator(),
            format,
            args) catch {
            return;
        };
        print(t, str);
        kernel.mm.kfree(str.ptr);
    }
    // fmt.format(writer, format, args) catch unreachable;
}

pub fn printfLen(comptime format: []const u8, args: anytype) u32 {
    if (screen.current_tty) |t| {
        const str = fmt.allocPrint(
            kernel.mm.kernel_allocator.allocator(),
            format,
            args) catch {
            return 0;
        };
        mtx.lock();
        defer mtx.unlock();
        t.print(str);
        const len = str.len;
        kernel.mm.kfree(str.ptr);
        return len;
    }
    return 0;
    // fmt.format(writer, format, args) catch unreachable;
}
