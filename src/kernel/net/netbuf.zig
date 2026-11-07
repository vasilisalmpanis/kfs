const krn = @import("../main.zig");
const std = @import("std");
const arp = @import("ipv4/arp.zig");
const ip = @import("ipv4/ip.zig");

var lst: ?*Netbuf = null;
var lock = krn.Spinlock.init();

pub fn enqueue(packet: *Netbuf) void {
    const state = lock.lock_irq_disable();
    defer lock.unlock_irq_enable(state);

    if (lst) |head| {
        head.lst.addTail(&packet.lst);
    } else {
        lst = packet;
    }
}

pub fn dequeue() ?*Netbuf {
    const state = lock.lock_irq_disable();
    defer lock.unlock_irq_enable(state);

    if (lst) |head| {
        if (head.lst.isEmpty()) {
            lst = null;
        } else {
            lst = head.lst.next.?.entry(Netbuf, comptime "lst");
        }
        head.lst.del();
        return head;
    }
    return null;
}

pub const Netbuf = struct {
    data: []u8,
    lst: krn.list.ListHead,
    pos: usize = 0,
    dev: *krn.net.dev.NetDevice,

    pub fn new(
        net_dev: *krn.net.dev.NetDevice,
        data_len: usize,
    ) ?*Netbuf {
        var netbuf = netbuf_cache.alloc() orelse
            return null;
        netbuf.lst.setup();
        netbuf.pos = 0;
        netbuf.data.len = data_len;
        if (data_len != 0) {
            netbuf.data = krn.mm.kmallocSlice(u8, data_len) orelse {
                netbuf_cache.free(netbuf);
                return null;
            };
            @memset(netbuf.data[0..data_len], 0);
        }
        netbuf.dev = net_dev;
        return netbuf;
    }

    pub fn release(self: *Netbuf) void {
        krn.mm.kfreeSlice(self.data);
        krn.mm.kfree(self);
    }

    pub fn pull(self: *Netbuf, num_of_bytes: usize) !void {
        if (self.pos + num_of_bytes > self.data.len)
            return krn.errors.PosixError.E2BIG;
        self.pos += num_of_bytes;
    }

    pub fn push(self: *Netbuf, num_of_bytes: usize) !void {
        if (num_of_bytes > self.pos)
            return krn.errors.PosixError.EOVERFLOW;
        self.pos -= num_of_bytes;
    }

    /// Writes the content of data buffer to the internal
    /// buffer of the netbuf and performs checks around
    /// data length.
    pub fn writeData(self: *Netbuf, data: []u8) !void {
        if (self.pos + data.len > self.data.len)
            return krn.errors.PosixError.E2BIG;
        @memcpy(self.data[self.pos..], data);
    }

    pub fn getPtr(self: *Netbuf, comptime t: type) *t {
        if (self.pos + @sizeOf(t) > self.data.len)
            @panic("Out-Of-Bounds cast");
        return @ptrCast(@alignCast(&self.data[self.pos]));
    }

    pub fn getEthernetHeader(self: *Netbuf) !*krn.net.EthernetHeader {
        if (self.data.len < @sizeOf(krn.net.EthernetHeader))
            return krn.errors.PosixError.EINVAL;
        return @ptrCast(@alignCast(self.data.ptr));
    }

    pub fn print(self: *Netbuf) void {
        const eth_h = self.getEthernetHeader() catch {
            krn.logger.INFO(
                "Packet on {s} is not correct eth",
                .{std.mem.sliceTo(&self.dev.name, 0)}
            );
            return ;
        };
        krn.logger.INFO(
            \\ === pkt begin ===
            \\   if:    {s}
            \\   src:   {x}
            \\   dest:  {x}
            \\   type:  {x}
            ,.{
                std.mem.sliceTo(&self.dev.name, 0),
                eth_h.src_mac,
                eth_h.dest_mac,
                std.mem.bigToNative(u16, eth_h.eth_type)
            }
        );
        switch (std.mem.bigToNative(u16, eth_h.eth_type)) {
            krn.net.ETH_P_ARP => {
                krn.logger.INFO("ETH_P_ARP", .{});
            },
            krn.net.ETH_P_IP => {
                krn.logger.INFO("ETH_P_IP", .{});
            },
            else => krn.logger.INFO("UNKNOWN TYPE", .{}),
        }
        krn.logger.INFO("=== pkt end ===", .{});
    }
};

fn process(_: ?*const anyopaque) i32 {
    while (true) {
        if (dequeue()) |netbuf| {
            defer netbuf.release();
            const eth_header = netbuf.getEthernetHeader() catch
                continue;
            // We don't operate in promiscuous mode so the NIC
            // is supposed to filter out packets other than broadcast
            // or with dst hardware address other than the NIC's

            netbuf.pull(@sizeOf(krn.net.EthernetHeader)) catch {};
            netbuf.print();

            if (switch (std.mem.bigToNative(u16, eth_header.eth_type)) {
                krn.net.ETH_P_ARP   => arp.arpReceive(netbuf) catch false,
                krn.net.ETH_P_IP    => ip.receive(netbuf) catch false,
                else                => false,
            }) {
                eth_header.makeReply(netbuf.dev);
                netbuf.dev.ops.xmit(netbuf) catch |err| {
                    krn.logger.WARN(
                        "Failed to xmit on {s}: {t}",
                        .{
                            std.mem.sliceTo(&netbuf.dev.name, 0),
                            err
                        }
                    );
                };
            }
        }
    }
    return 0;
}

var netbuf_cache = krn.mm.Cache(Netbuf).init("netbuf_cache");

pub fn init() !void {
    netbuf_cache.setup();
    _ = try krn.kthreadCreate(process, null, "netbuf_processor");
}
