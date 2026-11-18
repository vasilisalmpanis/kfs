const std = @import("std");
const krn = @import("../../main.zig");

pub var sockets: [256]?*krn.socket.Socket = @splat(null);
pub var lock = krn.Mutex.init();

pub fn add(sock: *krn.socket.Socket) void {
    lock.lock();
    defer lock.unlock();

    if (sockets[sock.protocol]) |head| {
        head.list.addTail(&sock.list);
    } else {
        sockets[sock.protocol] = sock;
    }
}

pub fn del(sock: *krn.socket.Socket) void {
    lock.lock();
    defer lock.unlock();

    if (sock.list.isEmpty()) {
        sockets[sock.protocol] = null;
    }
    sock.list.del();    
}

pub fn map(
    proto:  u8,
    func:   *const fn(*krn.socket.Socket,?*anyopaque) anyerror!void,
    arg:    ?*anyopaque
) !void {
    lock.lock();
    defer lock.unlock();

    if (sockets[proto]) |head| {
        var it = head.list.iterator();
        while (it.next()) |i| {
            const item = i.curr.entry(krn.socket.Socket, "list");
            try func(item, arg);
        }
    }
}

pub fn raw_input(socket: *krn.socket.Socket, _pkt: ?*krn.net.Netbuf) !void {
    const pkt = _pkt orelse
        return ;
    const new_pkt = pkt.clone() orelse
        return krn.errors.PosixError.ENOMEM;
    socket.enqueue(new_pkt);
}
