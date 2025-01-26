const screen = @import("drivers").screen;
const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;


pub const writer = Writer(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    const color: u8 = screen.current_tty.?._terminal_color;
    // Print the string passed to the callback
    if (screen.current_tty) |t|
        t.print(string, color, false);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    fmt.format(writer, format, args) catch unreachable;
}
