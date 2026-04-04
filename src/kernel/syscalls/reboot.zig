const krn = @import("../main.zig");
const system = @import("arch").system;
const errors = @import("error-codes.zig").PosixError;

const LINUX_REBOOT_MAGIC1 = 0xfee1dead;
const LINUX_REBOOT_MAGIC2 = 0x28121969;
const LINUX_REBOOT_MAGIC2A = 0x05121996;
const LINUX_REBOOT_MAGIC2B = 0x16041998;
const LINUX_REBOOT_MAGIC2C = 0x20112000;

const LINUX_REBOOT_CMD_RESTART      = 0x01234567;
const LINUX_REBOOT_CMD_HALT         = 0xCDEF0123;
const LINUX_REBOOT_CMD_POWER_OFF    = 0x4321FEDC;

fn validMagic2(v: u32) bool {
    return v == LINUX_REBOOT_MAGIC2
        or v == LINUX_REBOOT_MAGIC2A
        or v == LINUX_REBOOT_MAGIC2B
        or v == LINUX_REBOOT_MAGIC2C;
}

pub fn reboot(magic1: u32, magic2: u32, cmd: u32, _: u32, _: u32, _: u32) !u32 {
    if (magic1 != LINUX_REBOOT_MAGIC1 or !validMagic2(magic2))
        return errors.EINVAL;

    switch (cmd) {
        LINUX_REBOOT_CMD_RESTART    => system.reboot(),
        LINUX_REBOOT_CMD_HALT       => system.halt(),
        LINUX_REBOOT_CMD_POWER_OFF  => system.shutdown(),
        else                        => return errors.EINVAL,
    }
}
