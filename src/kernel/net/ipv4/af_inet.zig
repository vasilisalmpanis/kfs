const krn = @import("../../main.zig");
const uif = @import("../if.zig");
const in = @import("./main.zig");
const dev_ioctl = @import("../core/dev_ioctl.zig");

const devinet = @import("./dev.zig");
pub const IPv4Dev = devinet.IPv4Dev;

pub const IPv4Socket = struct {
    sock: krn.socket.Socket,

    fn connect(
        base: *krn.socket.Socket,
        addr_ptr: *anyopaque,
        addr_len: u32
    ) !void {
        _ = base;
        _ = addr_len;
        _ = addr_ptr;
        return krn.errors.PosixError.ENOSYS;
    }

    fn sendto(
        base: *krn.socket.Socket,
        buf: [*]const u8,
        size: usize
    ) !usize {
        _ = base;
        _ = buf;
        _ = size;
        return krn.errors.PosixError.ENOSYS;
    }
};

pub const inet_family = krn.socket.ProtocolFamily {
    .create = inet_create,
};


fn inet_create(socket_type: u16, protocol: u8) !*krn.socket.Socket {
    const socket = krn.mm.kmalloc(IPv4Socket) orelse
        return krn.errors.PosixError.ENOMEM;
    socket.sock.setup(krn.socket.AF_INET, socket_type, protocol);
    socket.sock.ops = &inet_raw_ops;
    return &socket.sock;
}

const inet_raw_ops = krn.socket.ProtocolOps{
    .ioctl      = inet_ioctl,
    .poll       = undefined,
    .accept     = undefined,
    .connect    = IPv4Socket.connect,
    .bind       = undefined,
    .recvfrom   = undefined,
    .sendto     = IPv4Socket.sendto,
    .listen     = undefined,
    .getName    = undefined,
    .socketpair = undefined,
    .release    = undefined,
};

fn inet_ioctl(
    socket: *krn.socket.Socket,
    op: u32,
    data: usize
) !u32 {
    _ = socket;
    switch (op) {
        uif.SIOCGIFDSTADDR => return krn.errors.PosixError.EADDRNOTAVAIL,
        else => {},
    }
    if (devinet.isDevinetIoctl(op))
        return devinet.devinetIoctl(op, data);
    if (dev_ioctl.isDevIoctl(op))
        return dev_ioctl.devIoctl(op, data);
    return krn.errors.PosixError.ENOTTY;
}
