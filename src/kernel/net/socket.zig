const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const Socket = struct {
    id: u32,
    _buffer: [128]u8,
    writer: std.Io.Writer,
    reader: std.Io.Reader,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Socket, id: u32) void {
        self.id = id;
        self._buffer = .{0} ** 128;
        self.writer = std.Io.Writer.fixed(&self._buffer);
        self.reader = std.Io.Reader.fixed(&self._buffer);
        self.conn = null;
        self.list.next = &self.list;
        self.list.prev = &self.list;
        self.lock = mutex.Mutex.init();
    }

    pub fn delete(self: *Socket) void {
        sockets_lock.lock();
        defer sockets_lock.unlock();
        self.lock.lock();
        self.list.del();
        if (self.conn) |remote| {
            remote.conn = null;
        }
        krn.mm.kfree(self);
    }
};

pub fn newSocket() ?*Socket {
    const sock: ?*Socket = krn.mm.kmalloc(Socket);
    if (sock) |_sock| {
        sockets_lock.lock();
        if (sockets) |first| {
            const id = first.prev.?.entry(Socket, "list").*.id;
            _sock.setup(id + 1);
            first.addTail(&_sock.list);
        } else {
            _sock.setup(1);
            sockets = &_sock.list;
        }
        sockets_lock.unlock();
    }
    return sock;
}

pub fn findById(id: u32) ?*Socket {
    sockets_lock.lock();
    defer sockets_lock.unlock();
    if (sockets) |first| {
        var it = first.iterator();
        while (it.next()) |i| {
            const sock = i.curr.entry(Socket, "list");
            if (sock.id == id)
                return sock;
        }
    }
    return null;
}

var sockets_lock: mutex.Mutex = mutex.Mutex.init();
pub var sockets: ?*lst.ListHead = null;
