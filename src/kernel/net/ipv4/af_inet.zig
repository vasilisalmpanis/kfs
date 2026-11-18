const krn = @import("../../main.zig");
const uif = @import("../if.zig");
const in = @import("./main.zig");
const dev_ioctl = @import("../core/dev_ioctl.zig");
const std = @import("std");
const routing = @import("route.zig");
const arp = @import("./arp.zig");

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
            return krn.errors.PosixError.ENOSYS;
        const payload = iovecs[0].base orelse
            return krn.errors.PosixError.EFAULT;
        const payload_len = iovecs[0].len;
        const name = msg.name orelse
            return krn.errors.PosixError.EDESTADDRREQ;
        if (msg.namelen < @sizeOf(krn.socket.sockaddr_in))
            return krn.errors.PosixError.EINVAL;
        const daddr_in: *krn.socket.sockaddr_in = @ptrCast(@alignCast(name));
        if (daddr_in.family != krn.socket.AF_INET)
            return krn.errors.PosixError.EAFNOSUPPORT;
        const out_if = routing.lookup(daddr_in.addr) orelse
            return krn.errors.PosixError.EHOSTUNREACH;
        const ip_len = krn.net.ipv4.IP_HEADER_LEN + payload_len;
        const packet_size = krn.net.ETH_HEADER_LEN + ip_len;
        const netbuf = krn.net.Netbuf.new(out_if, packet_size) orelse
            return krn.errors.PosixError.ENOMEM;
        defer netbuf.release();

        // Write ICMP packet content
        try netbuf.pull(packet_size - payload_len);
        try netbuf.writeData(payload[0..payload_len]);

        // Write the IP packet content
        try netbuf.push(krn.net.ipv4.IP_HEADER_LEN);
        const ipheader = netbuf.getPtr(krn.net.ipv4.ip.IpHeader);
        ipheader.vers_ihl = 0x45;
        ipheader.ttl = 64;
        ipheader.protocol = base.protocol;
        ipheader.frag_off = std.mem.nativeToBig(u16, krn.net.ipv4.ip.IP_DF);
        ipheader.tos = 0;
        ipheader.tot_len = std.mem.nativeToBig(u16, @intCast(ip_len));
        ipheader.id = 0;
        ipheader.saddr = @bitCast([4]u8{ 10, 0, 2, 15 });
        ipheader.daddr = daddr_in.addr;
        ipheader.check = std.mem.nativeToBig(u16, ipheader.csum());

        // No queueing for now, if the neighbor is not known drop
        // packet, next ping will find neighbor (they responded)
        // and icmp can go out.
        arp.output(netbuf, @bitCast(daddr_in.addr)) catch {
            return krn.errors.PosixError.EHOSTUNREACH;
        };
        return payload_len;
    }

    fn recvmsg(
        base: *krn.socket.Socket,
        msg: *krn.socket.MsgHdr,
        flags: u32
    ) !usize {
        _ = flags;
        const iovecs = try msg.iovecs();
        base.lock.lock();

        var new_pkt = base.dequeueNoLock();
        while (new_pkt == null) {
            if (base.file.flags & krn.fs.file.O_NONBLOCK != 0) {
                base.lock.unlock();
                return krn.errors.PosixError.EAGAIN;
            }

            var wq_node = krn.wq.WaitQueueNode.init(krn.task.current());
            wq_node.setup();

            base.rw_queue.addToQueue(&wq_node);
            base.lock.unlock();
            base.rw_queue.waitIfInQueue(&wq_node, true, 0);

            if (krn.task.current().hasPendingSignal())
                return krn.errors.PosixError.ERESTARTSYS;
            base.lock.lock();
            new_pkt = base.dequeueNoLock();
        }
        base.lock.unlock();

        const pkt = new_pkt.?;
        defer pkt.release();

        msg.namelen = 0;
        var ret_size: usize = 0;

        const ip_start: usize = krn.net.ETH_HEADER_LEN;
        if (pkt.data.len < ip_start + @sizeOf(krn.net.ipv4.ip.IpHeader))
            return krn.errors.PosixError.EINVAL;

        const ip_h: *align(1) const krn.net.ipv4.ip.IpHeader =
            @ptrCast(pkt.data[ip_start..].ptr);
        const ip_len: usize = std.mem.bigToNative(u16, ip_h.tot_len);

        if (ip_len < @sizeOf(krn.net.ipv4.ip.IpHeader) or
            ip_len > pkt.data.len - ip_start)
            return krn.errors.PosixError.EINVAL;

        const packet_data = pkt.data[ip_start..][0..ip_len];

        for (iovecs) |iov| {
            if (ret_size == packet_data.len)
                break;
            if (iov.len == 0)
                continue;
            const buf = iov.base orelse
                return if (ret_size > 0)
                    ret_size
                else
                    krn.errors.PosixError.EFAULT;
            const got = @min(iov.len, packet_data.len - ret_size);
            @memcpy(buf[0..got], packet_data[ret_size..][0..got]);
            ret_size += got;
            if (got < iov.len)
                break;
        }
        return ret_size;
    }

    fn release(base: *krn.socket.Socket) !void {
        const self: *IPv4Socket = @fieldParentPtr("sock", base);
        switch (self.sock.socket_type) {
            krn.socket.SOCK_RAW => krn.net.ipv4.raw.del(&self.sock),
            else => {
                // TODO: other types;
            },
        }
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
    switch (socket.sock.socket_type) {
        krn.socket.SOCK_RAW => krn.net.ipv4.raw.add(&socket.sock),
        else => {
            // TODO: other types
        },
    }
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
