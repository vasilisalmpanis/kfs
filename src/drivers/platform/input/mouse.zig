const krn = @import("kernel");
const arch = @import("arch");

const pdev = @import("../device.zig");
const pdrv = @import("../driver.zig");
const pbus = @import("../bus.zig");

const drv = @import("../../driver.zig");
const cdev = @import("../../cdev.zig");

var mouse_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "mice",
        .probe = undefined,
        .remove = undefined,
        .fops = &mouse_file_ops,
    },
    .probe = mouse_probe,
    .remove = mouse_remove,
};

const PacketBits = packed struct(u8) {
    bl: bool,
    br: bool,
    bm: bool,
    _1: bool,
    xs: bool,
    ys: bool,
    xo: bool,
    yo: bool,

    pub fn isButtonUp(self: *const PacketBits) bool {
        return (self._1 
            and !self.bl
            and !self.br
            and !self.bm
            and !self.xs
            and !self.ys
            and !self.xo
            and !self.yo
        );
    }

    pub fn isMotion(self: *const PacketBits) bool {
        return self.xs or self.ys or self.xo or self.yo;
    } 
};

const Mouse = struct {
    packet:         [4]u8 = .{0} ** 4,
    packet_cnt:     u8 = 0,
    packet_size:    u8 = 3,
    buff:           [512]u8 = .{0} ** 512,
    rb:             krn.ringbuf.RingBuf = undefined,
    wait_queue:     krn.wq.WaitQueueHead = krn.wq.WaitQueueHead.init(),

    pub fn new() ?*Mouse {
        if (krn.mm.kmalloc(Mouse)) |_m| {
            _m.setup() catch {
                krn.mm.kfree(_m);
                return null;
            };
            return _m;
        }
        return null;
    }

    pub fn setup(self: *Mouse) !void {
        self.* = Mouse{};
        self.rb = try krn.ringbuf.RingBuf._init(&self.buff);
        self.wait_queue.setup();
    }

    pub fn getMotion(self: *Mouse) struct {x: i32, y: i32} {
        var x: i32 = 0;
        var y: i32 = 0;
        const data: i32 = @intCast(self.packet[0]);
        if (self.packet[1] != 0)
            x = @as(i32, @intCast(self.packet[1])) - ((data << 4) & 0x100);
        if (self.packet[2] != 0)
            y = @as(i32, @intCast(self.packet[2])) - ((data << 3) & 0x100);
        return .{ .x = x, .y = y };
    }

    pub fn handlePacket(self: *Mouse) void {
        const bits: PacketBits = @bitCast(self.packet[0]);
        if (bits.bl) {
            krn.logger.INFO("Button LEFT", .{});
        } else if (bits.br) {
            krn.logger.INFO("Button RIGHT", .{});
        } else if (bits.bm) {
            krn.logger.INFO("Button MID", .{});
        } else if (bits.isMotion()) {
            krn.logger.INFO("Motion {any}", .{self.getMotion()});
        } else if  (bits.isButtonUp()) {
            krn.logger.INFO("Button UP", .{});
        }
    }

    pub fn consume(self: *Mouse, packet: u8) void {
        _ = self.rb.push(packet);
        self.wait_queue.wakeUpOne();
        self.packet[self.packet_cnt] = packet;
        self.packet_cnt += 1;
        if (self.packet_cnt == self.packet_size) {
            self.packet_cnt = 0;
            self.handlePacket();
        }
    }
};

pub export fn mouseHandler(_mouse: ?*anyopaque) void{
    if (_mouse == null)
        return ;
    const mouse: *Mouse = @ptrCast(@alignCast(_mouse.?));
    arch.io.outb(0x64, 0xA7);
    defer arch.io.outb(0x64, 0xA8);

    const packet = arch.io.inb(0x60);
    mouse.consume(packet);
}

fn mouse_probe(device: *pdev.PlatformDevice) !void {
    arch.cpu.disableInterrupts();
    waitPS2(true);
    arch.io.outb(0x64, 0xA8);
    waitPS2(true);
    arch.io.outb(0x64, 0x20);
    waitPS2(false);
    const status = arch.io.inb(0x60) | 2;
    waitPS2(true);
    arch.io.outb(0x64, 0x60);
    waitPS2(true);
    arch.io.outb(0x60, status);

    mouseWrite(0xF6); // set defaults
    _ = mouseRead();
    mouseWrite(0xF4); // enable data reporting
    _ = mouseRead();
    arch.cpu.enableInterrupts();
    krn.irq.registerHandler(12, mouseHandler, device.dev.data);

    try cdev.addCdev(
        &device.dev,
        krn.fs.UMode.chardev(),
        "/dev/input"
    );
}

fn mouse_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var mouse_file_ops = krn.fs.FileOps{
    .open = mouse_open,
    .close = mouse_close,
    .read = mouse_read,
    .write = mouse_write,
    .lseek = null,
    .readdir = null,
    .poll = mouse_poll,
};

fn mouse_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn mouse_close(_: *krn.fs.File) void {}

fn mouse_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    if (file.inode.data.dev) |_d| {
        const mouse: *Mouse = @ptrCast(@alignCast(_d.data.?));
        var to_read = size;
        const avail = mouse.rb.available();
        if (avail != 0) {
            if (avail < to_read)
                to_read = avail;
            if (to_read < mouse.packet_size)
                return 0;
            const rem = to_read % mouse.packet_size;
            if (rem != 0)
                to_read -= (mouse.packet_size - rem);
            return mouse.rb.readInto(buf[0..to_read]);
        }
        return 0;
    }
    return krn.errors.PosixError.EIO;
}

fn mouse_poll(
    file: *krn.fs.File,
    pollfd: *krn.poll.PollFd,
    poll_table: ?*krn.poll.PollTable
) !u32 {
    if (file.inode.data.dev) |_d| {
        if (_d.data) |data| {
            const mouse: *Mouse = @ptrCast(@alignCast(data));
            if (pollfd.events & krn.poll.POLLIN != 0) {
                if (mouse.rb.available() > 0) {
                    pollfd.revents |= krn.poll.POLLIN;
                } else if (poll_table) |pt| {
                    try pt.addNode(&mouse.wait_queue);
                }
            }
        }
    }
    if (pollfd.revents != 0)
        return 1;
    return 0;
}

fn mouse_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = file;
    _ = buf;
    return size;
}

fn mouseRead() u8{
    waitPS2(false);
    return arch.io.inb(0x60);
}

fn mouseWrite(value: u8) void{
    waitPS2(true);
    arch.io.outb(0x64, 0xD4);
    waitPS2(true);
    arch.io.outb(0x60, value);
}

fn waitPS2(input: bool) void {
    while (true) {
        const status = arch.io.inb(0x64);
        if (input) {
            if (status & 0x2 == 0) break; // input buffer empty, safe to write
        } else {
            if (status & 0x1 != 0) break; // output buffer full, data available to read
        }
    }
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT mouse", .{});
    if (pdev.PlatformDevice.alloc("mice")) |mouse_dev| {
        mouse_dev.dev.data = Mouse.new();
        if (mouse_dev.dev.data == null) {
            krn.logger.ERROR("Failed to alloc Mouse data", .{});
            return ;
        }
        mouse_dev.register() catch {
            krn.logger.ERROR("Failed to register mouse device", .{});
            if (mouse_dev.dev.data) |_m| krn.mm.kfree(_m);
            return ;
        };
        krn.logger.WARN("Device registered for /dev/mouse", .{});
        pdrv.platform_register_driver(&mouse_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            if (mouse_dev.dev.data) |_m| krn.mm.kfree(_m);
            return ;
        };
        krn.logger.WARN("Driver registered for /dev/mouse", .{});
        return ;
    }
    krn.logger.WARN("/dev/mouse cannot be initialized", .{});
}
