const krn = @import("../main.zig");
const std = @import("std");

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

    pub fn new(net_dev: *krn.net.dev.NetDevice) ?*Netbuf {
        var netbuf = krn.mm.kmalloc(Netbuf) orelse
            return null;
        netbuf.lst.setup();
        netbuf.pos = 0;
        netbuf.data.len = 0;
        netbuf.dev = net_dev;
        return netbuf;
    }
};

fn process(_: ?*const anyopaque) i32 {
    while (true) {
        if (dequeue()) |netbuf| {
            const eth_header: *krn.net.EthernetHeader = @ptrCast(
                @alignCast(netbuf.data.ptr)
            );
            switch (eth_header.eth_type) {
                krn.net.ETH_P_ARP => {},
                else => {},
            }
            krn.logger.INFO("eth: {any}", .{eth_header});
        }
    }
    return 0;
}

pub fn init() !void {
    _ = try krn.kthreadCreate(process, null, "netbuf_processor");
}
