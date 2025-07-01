const std = @import("std");
const vfs = @import("./vfs.zig");
const krn = @import("../main.zig");

pub const File = struct {
    f: vfs.IFileFields = .{
        .name = "",
        .size = 0,
        .permissions = 0o644,
        .fd = 0,
    },
    buff: [10:0]u8 = .{0} ** 10,

    pub fn init() !vfs.IFile {
        if (krn.mm.kmalloc(File)) |f| {
            return vfs.IFile.init(f);
        }
        return error.OutOfMemory;
    }

    pub fn open(self: *File, path: []const u8) !u32 {
        krn.logger.INFO("Opening file: {s}", .{path});
        self.f.fd = 42;
        self.f.name = path;
        self.f.size = 10; // Example size
        return self.f.fd;
    }
    
    pub fn release(self: *File) !u32 {
        krn.logger.INFO("Closing file with fd: {d}", .{self.f.fd});
        return 0;
    }
    
    pub fn write(self: *File, buff: [*]const u8, size: u32, _: *u32) !u32 {
        krn.logger.INFO("Writing {d} bytes to fd: {d}", .{ size, self.f.fd });
        const s = if (size > 10) 10 else size;
        @memcpy(self.buff[0..s], buff[0..s]);
        return s;
    }
    
    pub fn read(self: *File, buff: [*]u8, size: u32, _: *u32) !u32 {
        krn.logger.INFO("Reading {d} bytes from fd: {d}", .{ size, self.f.fd });
        const s = if (size > 10) 10 else size;
        @memcpy(buff[0..s], self.buff[0..s]);
        return s;
    }
};

pub fn test_file() !void {
    var file = try File.init();
    const fd = try file.open("test.txt");
    krn.logger.INFO("File opened with fd: {d}", .{fd});
    defer _ = file.release() catch |err| {
        krn.logger.ERROR("Error closing file: {!}", .{err});
    };

    const write_data = "HelloWorld";
    var off: u32 = 0;
    _ = try file.write(&write_data.*, write_data.len, &off);

    var read_buff: [10]u8 = .{0} ** 10;
    const bytes_read = try file.read(&read_buff, 10, &off);
    krn.logger.INFO("Read {d} bytes: {s}", .{bytes_read, read_buff[0..bytes_read]});
}
