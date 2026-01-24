const std = @import("std");
const krn = @import("../main.zig");
const mutex = @import("../sched/mutex.zig");

const BUFFER_SIZE = 2048;

pub const Pipe = struct {
    _buffer: [BUFFER_SIZE]u8,
    rb: krn.ringbuf.RingBuf,
    readers: u32 = 1,
    writers: u32 = 1,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Pipe) void {
        self._buffer = .{0} ** BUFFER_SIZE;
        self.readers = 1;
        self.writers = 1;
        self.rb = krn.ringbuf.RingBuf{
            .buf = self._buffer[0..BUFFER_SIZE],
            .mask = BUFFER_SIZE - 1,
        };
        self.lock = mutex.Mutex.init();
    }

    pub fn delete(self: *Pipe) void {
        self.lock.lock();
        krn.mm.kfree(self);
    }

    pub fn newPipe() ?*Pipe {
        const pipe: ?*Pipe = krn.mm.kmalloc(Pipe);
        if (pipe) |_pipe| {
            _pipe.setup();
        }
        return pipe;
    }
};

pub fn open(base: *krn.fs.File, inode: *krn.fs.Inode) !void {
    _ = base;
    _ = inode;
    krn.logger.INFO("pipe open", .{});
}

pub fn close(base: *krn.fs.File) void {
    krn.logger.INFO("pipe close", .{});
    const pipe = base.inode.data.pipe
        orelse return ;
    if (base.flags & krn.fs.file.O_WRONLY != 0) {
        pipe.writers -|= 1;
    } else if (base.flags & krn.fs.file.O_RDONLY != 0) {
        pipe.readers -|= 1;
    } else if (base.flags & krn.fs.file.O_RDWR != 0) {
        pipe.writers -|= 1;
        pipe.readers -|= 1;
    }
}

pub fn read(base: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    const pipe = base.inode.data.pipe
        orelse return krn.errors.PosixError.EFAULT;
    while (pipe.rb.isEmpty()) {
        if (pipe.writers == 0)
            return 0;
    }

    pipe.lock.lock();
    defer pipe.lock.unlock();
    const ret_size: usize = pipe.rb.readInto(buf[0..size]);
    return ret_size;
}

pub fn write(base: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    const pipe = base.inode.data.pipe
        orelse return krn.errors.PosixError.EFAULT;
    if (pipe.readers == 0) {
        return krn.errors.PosixError.EPIPE;
    }
    while (pipe.rb.isFull()) {
    }
    pipe.lock.lock();
    defer pipe.lock.unlock();
    for (buf[0..size], 0..) |ch, idx| {
        if (!pipe.rb.push(ch)) {
            return idx;
        }
    }
    return size;
}

pub const PipeFileOps: krn.fs.FileOps = krn.fs.FileOps {
    .open = open,
    .close = close,
    .write = write,
    .read = read,
};
