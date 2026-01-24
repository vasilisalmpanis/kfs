const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const Socket = struct {
    _buffer: [128]u8,
    rb: krn.ringbuf.RingBuf,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Socket) void {
        self._buffer = .{0} ** 128;
        self.rb = krn.ringbuf.RingBuf{
            .buf = self._buffer[0..128],
            .mask = 127,
        };
        self.conn = null;
        self.list.next = &self.list;
        self.list.prev = &self.list;
        self.lock = mutex.Mutex.init();
    }

    pub fn delete(self: *Socket) void {
        self.lock.lock();
        if (self.conn) |remote| {
            remote.conn = null;
        }
        krn.mm.kfree(self);
    }

    pub fn newSocket() ?*Socket {
        const sock: ?*Socket = krn.mm.kmalloc(Socket);
        if (sock) |_sock| {
            _sock.setup();
        }
        return sock;
    }
};

pub fn do_recvfrom(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    var sock: *krn.socket.Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    sock.lock.lock();
    defer sock.lock.unlock();
    if (!sock.rb.isEmpty()) {
        return sock.rb.readInto(buf[0..size]);
    }
    return 0;
}

pub fn do_sendto(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    var sock: *krn.socket.Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    if (sock.conn) |remote| {
        remote.lock.lock();
        defer remote.lock.unlock();
        for (buf[0..size], 0..) |ch, idx| {
            if (!remote.rb.push(ch))
                return idx;
        }
        return size;
    } else {
        return krn.errors.PosixError.ENOTCONN;
    }
}
pub fn open(base: *krn.fs.File, inode: *krn.fs.Inode) !void{
    _ = base;
    _ = inode;
}

pub fn close(base: *krn.fs.File) void{
    _ = base;
}
pub fn read(base: *krn.fs.File, buf: [*]u8, size: usize) !usize{
    return try do_recvfrom(base, buf, size);
}
pub fn write(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize{
    return try do_sendto(base, buf, size);
}

pub const SocketFileOps: krn.fs.FileOps = krn.fs.FileOps {
    .open = open,
    .close = close,
    .write = write,
    .read = read,
    .lseek = null,
    .readdir = null,
};
