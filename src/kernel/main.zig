const TTY = @import("tty.zig").TTY;

export fn kernel_main() noreturn {
    var tty = TTY.init(80, 25);
    tty.print("42\n");
    while (true) {}
}
