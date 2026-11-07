const krn = @import("../../main.zig");
const uif = @import("../if.zig");
const in = @import("./main.zig");
const dev_ioctl = @import("../core/dev_ioctl.zig");
const std = @import("std");

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

    fn sendmsg(
        base: *krn.socket.Socket,
        msg: *krn.socket.MsgHdr,
        flags: u32
    ) !usize {
        _ = flags;
        const iovecs = try msg.iovecs();
        if (iovecs.len != 1)
            krn.errors.PosixError.ENOSYS;
        if (msg.namelen < @sizeOf(krn.socket.sockaddr_in))
            krn.errors.PosixError.ENOSYS;
        const daddr_in: *krn.socket.sockaddr_in = @ptrCast(msg.name);
        if (daddr_in.family != krn.socket.AF_INET)
            krn.errors.PosixError.ENOSYS;
        const eth0 = krn.net.dev.getByIndex(0) orelse
            return krn.errors.PosixError.EHOSTUNREACH;
        const packet_size = krn.net.ETH_HEADER_LEN + krn.net.ipv4.IP_HEADER_LEN + iovecs[0].len;
        const netbuf = krn.net.Netbuf.new(eth0, packet_size) orelse
            return krn.errors.PosixError.ENOMEM;

        // Write ICMP packet content
        netbuf.pull(packet_size - iovecs[0].len);
        netbuf.writeData(iovecs[0].base.?[0..iovecs[0].len]);

        // Write the IP packet content
        netbuf.push(krn.net.ipv4.IP_HEADER_LEN);
        const ipheader = netbuf.getPtr(krn.net.ipv4.ip.IpHeader);
        ipheader.ttl = 64;
        ipheader.protocol = base.protocol;
        ipheader.frag_off = 0;
        ipheader.tos = 0;
        ipheader.tot_len = std.mem.nativeToBig(u16, packet_size - krn.net.ETH_HEADER_LEN);
        ipheader.id = 0;
        ipheader.saddr = @bitCast(.{
            10, 0, 2, 15
        });
        ipheader.daddr = daddr_in.addr;
        ipheader.check = ipheader.csum();

        // TODO: find neighbor and emit packet
        return krn.errors.PosixError.ENOSYS;
    }

    fn recvmsg(
        base: *krn.socket.Socket,
        msg: *krn.socket.MsgHdr,
        flags: u32
    ) !usize {
        _ = base;
        _ = msg;
        _ = flags;
        return krn.errors.PosixError.ENOSYS;
    }

    fn release(base: *krn.socket.Socket) !void {
        const self: *IPv4Socket = @fieldParentPtr("sock", base);
        krn.mm.kfree(self);
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
    .recvmsg    = IPv4Socket.recvmsg,
    .sendmsg    = IPv4Socket.sendmsg,
    .listen     = undefined,
    .getName    = undefined,
    .socketpair = undefined,
    .release    = IPv4Socket.release,
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
