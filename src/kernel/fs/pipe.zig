const std = @import("std");
const krn = @import("../main.zig");
const mutex = @import("../sched/mutex.zig");

pub const Pipe = struct {
    _buffer: [128]u8,
    writer: std.Io.Writer,
    reader: std.Io.Reader,
    readers: u32 = 1,
    writers: u32 = 1,
    lock: mutex.Mutex = mutex.Mutex.init(),

    pub fn setup(self: *Pipe) void {
        self._buffer = .{0} ** 128;
        self.readers = 1;
        self.writers = 1;
        self.writer = std.Io.Writer.fixed(&self._buffer);
        self.reader = std.Io.Reader.fixed(&self._buffer);
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

pub fn read(base: *krn.fs.File, buf: [*]u8, size: u32) !u32 {
    krn.logger.INFO("pipe read {d}", .{size});
    const pipe = base.inode.data.pipe
        orelse return krn.errors.PosixError.EFAULT;
    while (pipe.reader.end <= pipe.reader.seek) {
        if (pipe.writers == 0)
            return 0;
    }
    pipe.lock.lock();
    defer pipe.lock.unlock();
    const len = pipe.reader.readSliceShort(buf[0..size]) catch {
        return krn.errors.PosixError.EIO;
    };
    return len;
}

pub fn write(base: *krn.fs.File, buf: [*]const u8, size: u32) !u32 {
    krn.logger.INFO("pipe write {d}", .{size});
    const pipe = base.inode.data.pipe
        orelse return krn.errors.PosixError.EFAULT;
    if (pipe.readers == 0) {
        return krn.errors.PosixError.EPIPE;
    }
    pipe.lock.lock();
    defer pipe.lock.unlock();
    const len = pipe.writer.write(buf[0..size]) catch {
        return krn.errors.PosixError.EIO;
    };
    return len;
}

pub const PipeFileOps: krn.fs.FileOps = krn.fs.FileOps {
    .open = open,
    .close = close,
    .write = write,
    .read = read,
};
