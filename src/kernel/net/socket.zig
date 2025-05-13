const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");

pub const Socket = struct {
    id: u32,
    buffer: [128]u8,
    conn: ?*Socket,
    list: lst.ListHead,

    pub fn setup(self: *Socket, id: u32) void {
        self.id = id;
        self.buffer = .{0} ** 128;
        self.conn = null;
        self.list.next = &self.list;
        self.list.prev = &self.list;
    }

    pub fn delete(self: *Socket) void {
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
    if (sockets) |first| {
        const id = first.prev.?.entry(Socket, "list").*.id;
        sock.setup(id + 1);
        first.addTail(&sock.list);
    } else {
        sock.setup(1);
        sockets = &sock.list;
    }
    return sock;
}

pub fn findById(id: u32) ?*Socket {
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

pub var sockets: ?*lst.ListHead = null;
