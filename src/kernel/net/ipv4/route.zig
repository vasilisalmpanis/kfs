// IPv4 routing table
//
// Mask and prefix length
//
//   address  10.0.2.15        00001010.00000000.00000010.00001111
//   mask     255.255.255.0    11111111.11111111.11111111.00000000
//                             |<---- network /24 ----->| <-host->
//   dst      10.0.2.0         address & mask (host bits cleared)
//
//   prefix length = number of 1 bits in the mask = @popCount(mask)
//
//   255.255.255.255  /32  one host
//   255.255.255.0    /24  256 addresses
//   255.0.0.0        /8   16M addresses
//   0.0.0.0          /0   everything (default)
//
// Lookup: longest prefix match
//
//   table                        daddr 10.0.2.2   daddr 10.0.2.9   daddr 10.5.5.5
//   10.0.0.0/8    dev eth1       match            match            match  <- wins
//   10.0.2.0/24   dev eth0       match            match  <- wins   -
//   10.0.2.2/32   dev eth2       match  <- wins   -                -
//
//   A route matches when (daddr & mask) == dst. Of all matching
//   routes the one with the longest prefix wins.
//   On equal prefix length the route added first wins.

const krn = @import("../../main.zig");
const socket = @import("../socket.zig");

pub const RTF_UP        : u16 = 0x0001;
pub const RTF_GATEWAY   : u16 = 0x0002;
pub const RTF_HOST      : u16 = 0x0004;
pub const RTF_REJECT    : u16 = 0x0200;

/// include/uapi/linux/route.h comes from userspace
pub const RtEntry = extern struct {
    pad1:       u32,
    dst:        socket.sockaddr,
    gateway:    socket.sockaddr,
    genmask:    socket.sockaddr,
    flags:      u16,
    pad2:       i16,
    pad3:       u32,
    pad4:       usize,
    metric:     i16,
    dev:        ?[*:0]const u8,
    mtu:        u32,
    window:     u32,
    irtt:       u16,
};

pub const Route = struct {
    list:       krn.list.ListHead,
    dst:        u32,
    mask:       u32,
    flags:      u16,
    dev:        *krn.net.dev.NetDevice,

    fn prefixLen(self: *const Route) u32 {
        return @popCount(self.mask);
    }
};

var routes: ?*Route = null;
var routes_lock = krn.Mutex.init();

pub fn add(
    dev: *krn.net.dev.NetDevice,
    dst: u32,
    mask: u32,
) !void {
    if (dst & ~mask != 0)
        return krn.errors.PosixError.EINVAL;

    const rt = krn.mm.kmalloc(Route) orelse
        return krn.errors.PosixError.ENOMEM;
    rt.* = .{
        .list = krn.list.ListHead.init(),
        .dst = dst,
        .mask = mask,
        .flags = RTF_UP,
        .dev = dev,
    };
    rt.list.setup();
    if (mask == 0xFFFF_FFFF)
        rt.flags |= RTF_HOST;

    routes_lock.lock();
    defer routes_lock.unlock();

    if (routes) |head| {
        var it = head.list.iterator();
        while (it.next()) |node| {
            const curr = node.curr.entry(Route, "list");
            if (curr.dst == dst and curr.mask == mask and curr.dev == dev) {
                krn.mm.kfree(rt);
                return krn.errors.PosixError.EEXIST;
            }
        }
        head.list.addTail(&rt.list);
    } else {
        routes = rt;
    }
}

pub fn lookup(daddr: u32) ?*krn.net.dev.NetDevice {
    routes_lock.lock();
    defer routes_lock.unlock();

    const head = routes orelse
        return null;
    var best: ?*Route = null;
    var it = head.list.iterator();
    while (it.next()) |node| {
        const curr = node.curr.entry(Route, "list");
        if (daddr & curr.mask != curr.dst)
            continue;
        if (best) |b| {
            if (curr.prefixLen() <= b.prefixLen())
                continue;
        }
        best = curr;
    }
    const rt = best orelse
        return null;
    return rt.dev;
}

pub fn del(dev: *krn.net.dev.NetDevice, dst: u32, mask: u32) bool {
    routes_lock.lock();
    defer routes_lock.unlock();

    const head = routes orelse
        return false;
    var it = head.list.iterator();
    while (it.next()) |node| {
        const curr = node.curr.entry(Route, "list");
        if (curr.dst != dst or curr.mask != mask or curr.dev != dev)
            continue;
        if (routes == curr) {
            routes = if (curr.list.isEmpty())
                null
            else
                curr.list.next.?.entry(Route, "list");
        }
        curr.list.del();
        krn.mm.kfree(curr);
        return true;
    }
    return false;
}
