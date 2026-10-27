const std = @import("std");
const socket = @import("./socket.zig");
const dev = @import("./core/dev.zig");

pub const IFNAMSIZ = 16;

pub const IFF_UP: i16           = 1 << 0;
pub const IFF_BROADCAST: i16    = 1 << 1;
pub const IFF_LOOPBACK: i16     = 1 << 3;
pub const IFF_RUNNING: i16      = 1 << 6;
pub const IFF_PROMISC: i16      = 1 << 8;
pub const IFF_MULTICAST: i16    = 1 << 12;

pub const ARPHRD_ETHER: u16     = 1;

pub const SIOCGIFNAME: u32      = 0x8910;
pub const SIOCGIFCONF: u32      = 0x8912;
pub const SIOCGIFFLAGS: u32     = 0x8913;
pub const SIOCSIFFLAGS: u32     = 0x8914;
pub const SIOCGIFADDR: u32      = 0x8915;
pub const SIOCSIFADDR: u32      = 0x8916;
pub const SIOCGIFDSTADDR: u32   = 0x8917;
pub const SIOCSIFDSTADDR: u32   = 0x8918;
pub const SIOCGIFBRDADDR: u32   = 0x8919;
pub const SIOCSIFBRDADDR: u32   = 0x891a;
pub const SIOCGIFNETMASK: u32   = 0x891b;
pub const SIOCSIFNETMASK: u32   = 0x891c;
pub const SIOCGIFMETRIC: u32    = 0x891d;
pub const SIOCSIFMETRIC: u32    = 0x891e;
pub const SIOCGIFMTU: u32       = 0x8921;
pub const SIOCSIFMTU: u32       = 0x8922;
pub const SIOCSIFNAME: u32      = 0x8923;
pub const SIOCSIFHWADDR: u32    = 0x8924;
pub const SIOCGIFHWADDR: u32    = 0x8927;
pub const SIOCGIFINDEX: u32     = 0x8933;
pub const SIOCGIFTXQLEN: u32    = 0x8942;
pub const SIOCSIFTXQLEN: u32    = 0x8943;
pub const SIOCGIFMAP: u32       = 0x8970;
pub const SIOCSIFMAP: u32       = 0x8971;

pub const Ifmap = extern struct {
    mem_start: u32,
    mem_end: u32,
    base_addr: u16,
    irq: u8,
    dma: u8,
    port: u8,
};

pub const Ifreq = extern struct {
    ifr_name: [IFNAMSIZ]u8,
    ifr_ifru: extern union {
        addr: socket.sockaddr,
        flags: i16,
        ivalue: i32,
        mtu: i32,
        map: Ifmap,
        slave: [IFNAMSIZ]u8,
        newname: [IFNAMSIZ]u8,
        data: usize,
    },

    pub fn name(self: *const Ifreq) []const u8 {
        return std.mem.sliceTo(self.ifr_name[0 .. IFNAMSIZ - 1], 0);
    }
};

pub const Ifconf = extern struct {
    ifc_len: i32,
    ifc_buf: usize,
};
