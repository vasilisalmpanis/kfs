const errors = @import("./error-codes.zig").PosixError;
const drv = @import("drivers");
const std = @import("std");
const krn = @import("../main.zig");

var _kshell: ?drv.shell.Shell = null;

pub fn kshell(args: ?*[][]const u8) !u32 {
    if (_kshell == null) {
        _kshell = drv.shell.Shell.init();
    }
    if (args) |_args| {
        const cmd = _args.*[0];
        const _a = _args.*[1..];
        if (_kshell) |shell| {
            var sh = shell;
            sh.exec(cmd, _a);
        }
    }
    return 0;
}
