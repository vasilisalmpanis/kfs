const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const Socket = struct {
    id: u32,
    _buffer: [128]u8,
    ringbuf: std.RingBuffer,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Socket, id: u32) void {
        self.id = id;
        self._buffer = .{0} ** 128;
        var fbe = std.heap.FixedBufferAllocator.init(&self._buffer);
        self.ringbuf = std.RingBuffer.init(fbe.allocator(), 128) catch std.RingBuffer{
            .data = &self._buffer,
            .read_index =  0,
            .write_index = 0,
        };
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
        krn.mm.kfree(@intFromPtr(self));
    }
};

pub fn newSocket() ?*Socket {
    const new_ptr = krn.mm.kmalloc(@sizeOf(Socket));
    if (new_ptr == 0) {
        return null;
    }
    var sock: *Socket = @ptrFromInt(new_ptr);
    sockets_lock.lock();
    if (sockets) |first| {
        const id = first.prev.?.entry(Socket, "list").*.id;
        sock.setup(id + 1);
        first.addTail(&sock.list);
    } else {
        sock.setup(1);
        sockets = &sock.list;
    }
    sockets_lock.unlock();
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
