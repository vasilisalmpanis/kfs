const krn = @import("kernel");

const pdev = @import("./device.zig");
const pdrv = @import("./driver.zig");
const pbus = @import("./bus.zig");

const drv = @import("../driver.zig");
const cdev = @import("../cdev.zig");

const FBIOGET_VSCREENINFO: u32 = 0x4600;
const FBIOPUT_VSCREENINFO: u32 = 0x4601;
const FBIOGET_FSCREENINFO: u32 = 0x4602;

const FBBitfield = extern struct {
	offset: u32 = 0,		// beginning of bitfield
	length: u32 = 0,		// length of bitfield
	msb_right: u32 = 0,		// != 0 : Most significant bit is
					// right
};

const FBFixScreeninfo = extern struct{
	id: [16]u8 = .{0} ** 16,	// identification string eg "TT Builtin"
	smem_start: u32 = 0,	        // Start of frame buffer mem
					// (physical address)
	smem_len: u32 = 0,		// Length of frame buffer mem
	ty: u32 = 0,			// see FB_TYPE_
	type_aux: u32 = 0,		// Interleave for interleaved Planes
	visual: u32 = 2,		// see FB_VISUAL
	xpanstep: u16 = 0,		// zero if no hardware panning
	ypanstep: u16 = 0,		// zero if no hardware panning
	ywrapstep: u16 = 0,		// zero if no hardware ywrap
	line_length: u32 = 0,		// length of a line in bytes
	mmio_start: u32 = 0,            // Start of Memory Mapped I/O
					// (physical address)
	mmio_len: u32 = 0,		// Length of Memory Mapped I/O
	accel: u32 = 0,			// Indicate to driver which
					//  specific chip/card we have
	capabilities: u16 = 0,		// see FB_CAP_/
	reserved: [2]u16 = .{0} ** 2,	// Reserved for future compatibility
};

const FBVarScreeninfo = extern struct {
	xres: u32 = 0,			// visible resolution
	yres: u32 = 0,
	xres_virtual: u32 = 0,		// virtual resolution
	yres_virtual: u32 = 0,
	xoffset: u32 = 0,		// offset from virtual to visible
	yoffset: u32 = 0,		// resolution

	bits_per_pixel: u32 = 0,	// guess what
	grayscale: u32 = 0,             // 0 = color, 1 = grayscale
					// >1 = FOURCC
	red:    FBBitfield = .{ .offset = 16, .length = 8, .msb_right = 0 }, // bitfield in fb mem if true color,
	green:  FBBitfield = .{ .offset =  8, .length = 8, .msb_right = 0 }, // else only length is significant
	blue:   FBBitfield = .{ .offset =  0, .length = 8, .msb_right = 0 },
	transp: FBBitfield = .{ .offset = 24, .length = 8, .msb_right = 0 }, // transparency

	nonstd: u32 = 0,		// != 0 Non standard pixel format

	activate: u32 = 0,	        // see FB_ACTIVATE_

	height: u32 = 0,		// height of picture in mm
	width: u32 = 0,			// width of picture in mm

	accel_flags: u32 = 0,		// (OBSOLETE) see fb_info.flags

	// Timing: All values in pixclocks = 0, except pixclock (of course)
	pixclock: u32 = 0,		// pixel clock in ps (pico seconds)
	left_margin: u32 = 0,		// time from sync to picture
	right_margin: u32 = 0,		// time from picture to sync
	upper_margin: u32 = 0,		// time from sync to picture
	lower_margin: u32 = 0,
	hsync_len: u32 = 0,		// length of horizontal sync
	vsync_len: u32 = 0,		// length of vertical sync
	sync: u32 = 0,			// see FB_SYNC
	vmode: u32 = 0,			// see FB_VMODE
	rotate: u32 = 0,		// angle we rotate counter clockwise
	colorspace: u32 = 0,		// colorspace for FOURCC-based modes
	reserved: [4]u32 = .{0} ** 4,	// Reserved for future compatibility
};

var fb_driver = pdrv.PlatformDriver {
    .driver = drv.Driver {
        .list = undefined,
        .name = "fb",
        .probe = undefined,
        .remove = undefined,
        .fops = &fb_file_ops,
    },
    .probe = fb_probe,
    .remove = fb_remove,
};

fn fb_probe(device: *pdev.PlatformDevice) !void {
    try cdev.addCdev(&device.dev, krn.fs.UMode.chardev(), null);
}

fn fb_remove(device: *pdev.PlatformDevice) !void {
    _ = device;
}

var fb_file_ops = krn.fs.FileOps{
    .open = fb_open,
    .close = fb_close,
    .read = fb_read,
    .write = fb_write,
    .lseek = null,
    .readdir = null,
    .ioctl = fb_ioctl,
    .mmap = fb_mmap,
};

fn fb_open(_: *krn.fs.File, _: *krn.fs.Inode) !void {}

fn fb_close(_: *krn.fs.File) void {}

fn fb_mmap(_: *krn.fs.File, vma: *krn.mm.VMA) !void{
    // remap physical memory of FB to userspace mapping
    // start of physical memory, end calculate pages
    const tag = krn.screen.framebuffer.fb_info;
    const num_pages = (vma.end - vma.start) / krn.mm.PAGE_SIZE;
    var i: usize = 0;
    var addr: usize = @truncate(tag.addr);
    addr &= ~@as(usize, 0xFFF);
    const lock_state = krn.mm.mem_lock.lock_irq_disable();
    var virt_addr = vma.start;
    while (i < num_pages) : (i += 1) {
        krn.mm.virt_memory_manager.mapPage(
            virt_addr,
            addr,
            .{
                .write_through = true,
                .writable = vma.prot & krn.mm.PROT_WRITE != 0,
                .user = true
            },
        );
        virt_addr += krn.mm.PAGE_SIZE;
        addr += krn.mm.PAGE_SIZE;
    }
    krn.mm.mem_lock.unlock_irq_enable(lock_state);
}
fn fb_ioctl(base: *krn.fs.File, op: u32, data: usize) !u32{
    _ = base;
    const data_ptr: ?*anyopaque = if (data == 0) null else @ptrFromInt(data);
    switch (op) {
        FBIOGET_VSCREENINFO => {
            if (data_ptr) |ptr| {
                const info = krn.screen.framebuffer.fb_info;
                const var_screen_info: *FBVarScreeninfo = @ptrCast(@alignCast(ptr));
                var_screen_info.* = FBVarScreeninfo{};
                var_screen_info.bits_per_pixel = info.bpp;
                var_screen_info.xres = info.width;
                var_screen_info.xres_virtual = info.width;
                var_screen_info.yres = info.height;
                var_screen_info.yres_virtual = info.height;
                var_screen_info.width  = (info.width * 26) / 96;
                var_screen_info.height = (info.height * 26) / 96;
            }
        },
        FBIOPUT_VSCREENINFO => {},
        FBIOGET_FSCREENINFO => {
            if (data_ptr) |ptr| {
                const info = krn.screen.framebuffer.fb_info;
                const fix_screen_info: *FBFixScreeninfo = @ptrCast(@alignCast(ptr));
                fix_screen_info.* = FBFixScreeninfo{};
                fix_screen_info.smem_start = @intCast(info.addr);
                fix_screen_info.smem_len = info.height * info.pitch;
                fix_screen_info.line_length = info.pitch;
                @memcpy(fix_screen_info.id[0..10], "TT Builtin");
            }
        },
        else  => return krn.errors.PosixError.EINVAL,
    }
    return 0;
}

fn fb_read(file: *krn.fs.File, buf: [*]u8, size: usize) !usize {
    _ = file;
    _ = buf;
    _ = size;
    return 0;
}

fn fb_write(file: *krn.fs.File, buf: [*]const u8, size: usize) !usize {
    _ = file;
    _ = buf;
    return size;
}

pub fn init() void {
    krn.logger.DEBUG("DRIVER INIT fb", .{});
    if (pdev.PlatformDevice.alloc("fb0")) |fb_dev| {
        fb_dev.register() catch {
            return ;
        };
        krn.logger.WARN("Device registered for /dev/fb0", .{});
        pdrv.platform_register_driver(&fb_driver.driver) catch |err| {
            krn.logger.ERROR("Error registering platform driver: {any}", .{err});
            return ;
        };
        krn.logger.WARN("Driver registered for /dev/fb", .{});
        return ;
    }
    krn.logger.WARN("/dev/fb cannot be initialized", .{});
}
