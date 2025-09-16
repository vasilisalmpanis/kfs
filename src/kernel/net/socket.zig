const std = @import("std");
const krn = @import("../main.zig");
const lst = @import("../utils/list.zig");
const mutex = @import("../sched/mutex.zig");

pub const Socket = struct {
    _buffer: [128]u8,
    writer: std.Io.Writer,
    reader: std.Io.Reader,
    conn: ?*Socket,
    list: lst.ListHead,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Socket) void {
        self._buffer = .{0} ** 128;
        self.writer = std.Io.Writer.fixed(&self._buffer);
        self.reader = std.Io.Reader.fixed(&self._buffer);
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

pub fn do_recvfrom(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    var sock: *krn.socket.Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    sock.lock.lock();
    const avail = sock.reader.end - sock.reader.seek;
    const to_read = if (avail > size) size else avail;
    defer sock.lock.unlock();
    _ = sock.reader.readSliceShort(buf[0..to_read]) catch {};
    return @intCast(to_read);
}

pub fn do_sendto(base: *krn.fs.File, buf: [*]const u8, size: u32) !u32 {
    var sock: *krn.socket.Socket = undefined;
    if (base.inode.data.sock == null) return krn.errors.PosixError.EBADF;
    sock = base.inode.data.sock.?;
    if (sock.conn) |remote| {
        krn.logger.INFO("sending data {d} \n", .{krn.task.current.pid});
        remote.lock.lock();
        defer remote.lock.unlock();
        const res = remote.writer.write(buf[0..size]) catch 0;
        return @intCast(res);
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
pub fn read(base: *krn.fs.File, buf: [*]u8, size: u32) !u32{
    return try do_recvfrom(base, buf, size);
}
pub fn write(base: *krn.fs.File, buf: [*]const u8, size: u32) !u32{
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
