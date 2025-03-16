const screen = @import("drivers").screen;
const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;


pub const writer = Writer(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    // Print the string passed to the callback
    if (screen.current_tty) |t|
        t.print(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    if (screen.current_tty) |t| {
        var buf: [2000]u8 = undefined;
        const str = fmt.bufPrint(&buf, format, args) catch {
            return ;
        };
        t.print(str);
    }
    // fmt.format(writer, format, args) catch unreachable;
}
