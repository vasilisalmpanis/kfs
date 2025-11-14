const errors = @import("./error-codes.zig").PosixError;
const krn = @import("../main.zig");

const Utsname = extern struct {
    sysname:    [65]u8,
    nodename:   [65]u8,
    release:    [65]u8,
    version:    [65]u8,
    machine:    [65]u8,
    domainname: [65]u8,
};

pub fn uname(ptr: ?*Utsname) !u32 {
    if (ptr == null) {
        return errors.EFAULT;
    }
    const sysname       = "kfs";
    const nodename      = "kfs-node";
    const release       = "0.1";
    const version       = "v0.1";
    const machine       = "x86";
    const domainname   = "localdomain";
    const user_ptr = ptr.?;
    @memcpy(user_ptr.*.sysname[0..sysname.len], sysname);
    @memcpy(user_ptr.*.nodename[0..nodename.len], nodename);
    @memcpy(user_ptr.*.release[0..release.len], release);
    @memcpy(user_ptr.*.version[0..version.len], version);
    @memcpy(user_ptr.*.machine[0..machine.len], machine);
    @memcpy(user_ptr.*.domainname[0..domainname.len], domainname);
    user_ptr.*.sysname[sysname.len] = 0;
    user_ptr.*.nodename[nodename.len] = 0;
    user_ptr.*.release[release.len] = 0;
    user_ptr.*.version[version.len] = 0;
    user_ptr.*.machine[machine.len] = 0;
    user_ptr.*.domainname[domainname.len] = 0;
    return 0;
}
