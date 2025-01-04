const TTY = @import("tty.zig").TTY;

export fn kernel_main() noreturn {
    const tty = TTY.init(80, 25);
    tty.print("42", 3);
    while (true) {}
}
