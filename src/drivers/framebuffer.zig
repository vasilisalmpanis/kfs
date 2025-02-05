const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;

pub const FrameBuffer = struct {
    fb_info: multiboot.FramebufferInfo,
    fb_ptr: [*]u32,
    cwidth: u32,
    cheight: u32,
    virtual_buffer: [*]u32,

    pub fn init(boot_info: *multiboot.multiboot_info) FrameBuffer {
        const fb_info: ?multiboot.FramebufferInfo = multiboot.getFBInfo(boot_info);
        const fb_size: u32 = fb_info.?.height * fb_info.?.pitch;
        const num_pages = (fb_size + 0xFFF) / mm.PAGE_SIZE;
        var i: u32 = 0;
        var addr = fb_info.?.address & 0xFFFFF000;
        var virt_addr: u32 = mm.virt_memory_manager.find_free_space(
            num_pages,
            mm.PAGE_OFFSET,
            0xFFFFF000,
            false
        );
        const first_addr: u32 = virt_addr;
        while (i < num_pages) : (i += 1) {
            mm.virt_memory_manager.map_page(virt_addr, addr, false);
            mm.virt_memory_manager.map_page(addr, addr, false);
            virt_addr += mm.PAGE_SIZE;
            addr += mm.PAGE_SIZE;
        }
        var fb = FrameBuffer{
            .fb_info = fb_info.?,
            .fb_ptr = @ptrFromInt(first_addr),
            .cwidth = (fb_info.?.pitch / 4) / 8,
            .cheight = fb_info.?.height / 16,
            .virtual_buffer = @ptrFromInt(mm.kmalloc(fb_info.?.width * fb_info.?.height * @sizeOf(u32))),
        };
        fb.clear();
        return fb;
    }

    pub fn render(self: *FrameBuffer) void {
        const max_index = self.fb_info.height * self.fb_info.width;
        @memcpy(self.fb_ptr[0..max_index], self.virtual_buffer[0..max_index]);
    }

    pub fn clear(self: *FrameBuffer) void {
        @memset(self.virtual_buffer[0 .. self.fb_info.height * self.fb_info.width], 0);
    }

    pub fn putchar(
        self: *FrameBuffer,
        c: u8,
        cx: u32,
        cy: u32,
        bg: u32,
        fg: u32,
    ) void {
        const char_data = font[c];
        const x = cx * 8;
        const y = cy * 16;
        for (0..16) |row| {
            for (0..8) |bit| {
                const b: u3 = @intCast(bit);
                const one: u8 = 1;
                const mask: u8 = one << (7 - b);
                if (c == 0) {
                    self.virtual_buffer[(row + y) * (self.fb_info.pitch / 4) + b + x] = bg;
                } else if ((char_data[row] & mask) != 0) {
                    self.virtual_buffer[(row + y) * (self.fb_info.pitch / 4) + b + x] = fg;
                } else {
                    self.virtual_buffer[(row + y) * (self.fb_info.pitch / 4) + b + x] = bg;
                }
            }
        }
    }

    pub fn cursor(
        self: *FrameBuffer,
        cx: u32,
        cy: u32,
        fg: u32,
    ) void {
        const x = cx * 8;
        const y = cy * 16;
        for (0..8) |pos| {
            self.virtual_buffer[(y + 14) * (self.fb_info.pitch / 4) + x + pos] = fg;
            self.virtual_buffer[(y + 15) * (self.fb_info.pitch / 4) + x + pos] = fg;
        }
    }
};

const font = [256][16]u8{
    [_]u8{ 0x10, 0x00, 0x00, 0x3C, 0x42, 0x99, 0xA5, 0xA1, 0xA1, 0xA5, 0x99, 0x42, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 0 (0x00)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 1 (0x01)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDB, 0xDB, 0x00, 0x00, 0x00 }, // ASCII 2 (0x02)
    [_]u8{ 0x00, 0x00, 0x00, 0xF1, 0x5B, 0x55, 0x51, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 3 (0x03)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x38, 0x7C, 0xFE, 0x7C, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00 }, // ASCII 4 (0x04)
    [_]u8{ 0x00, 0x00, 0x00, 0xCC, 0xCF, 0xED, 0xFF, 0xFC, 0xDF, 0xCC, 0xCC, 0xCC, 0xCC, 0x00, 0x00, 0x00 }, // ASCII 5 (0x05)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x3C, 0x66, 0x66, 0x66, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00 }, // ASCII 6 (0x06)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x3C, 0x3C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 7 (0x07)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 8 (0x08)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 9 (0x09)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x44, 0xBA, 0xB2, 0xAA, 0x44, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 10 (0x0A)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 11 (0x0B)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x0C, 0x38 }, // ASCII 12 (0x0C)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 13 (0x0D)
    [_]u8{ 0x00, 0x10, 0x38, 0x6C, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 14 (0x0E)
    [_]u8{ 0x00, 0x6C, 0x6C, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 15 (0x0F)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 16 (0x10)
    [_]u8{ 0x00, 0x18, 0x3C, 0x42, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 17 (0x11)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 18 (0x12)
    [_]u8{ 0x00, 0x10, 0x38, 0x44, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 19 (0x13)
    [_]u8{ 0x00, 0x00, 0x00, 0x7F, 0xDB, 0xDB, 0xDB, 0x7B, 0x1B, 0x1B, 0x1B, 0x1B, 0x1B, 0x00, 0x00, 0x00 }, // ASCII 20 (0x14)
    [_]u8{ 0x00, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x6C, 0xC6, 0xC6, 0x6C, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x00 }, // ASCII 21 (0x15)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 22 (0x16)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 23 (0x17)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x3C, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 24 (0x18)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x3C, 0x18, 0x00, 0x00, 0x00 }, // ASCII 25 (0x19)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x06, 0xFF, 0x06, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 26 (0x1A)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x60, 0xFF, 0x60, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 27 (0x1B)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 28 (0x1C)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x0C, 0xF8 }, // ASCII 29 (0x1D)
    [_]u8{ 0x00, 0x6C, 0x38, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 30 (0x1E)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x38, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 31 (0x1F)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 32 (0x20)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x3C, 0x3C, 0x3C, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 33 (0x21)
    [_]u8{ 0x00, 0x00, 0x66, 0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 34 (0x22)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x6C, 0x6C, 0xFE, 0x6C, 0x6C, 0x6C, 0xFE, 0x6C, 0x6C, 0x00, 0x00, 0x00 }, // ASCII 35 (0x23)
    [_]u8{ 0x00, 0x18, 0x18, 0x7C, 0xC6, 0xC2, 0xC0, 0x7C, 0x06, 0x06, 0x86, 0xC6, 0x7C, 0x18, 0x18, 0x00 }, // ASCII 36 (0x24)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0xC2, 0xC6, 0x0C, 0x18, 0x30, 0x60, 0xC6, 0x86, 0x00, 0x00, 0x00 }, // ASCII 37 (0x25)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x6C, 0x6C, 0x38, 0x76, 0xDC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 38 (0x26)
    [_]u8{ 0x00, 0x00, 0x30, 0x30, 0x30, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 39 (0x27)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00 }, // ASCII 40 (0x28)
    [_]u8{ 0x00, 0x00, 0x00, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00, 0x00, 0x00 }, // ASCII 41 (0x29)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 42 (0x2A)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 43 (0x2B)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x30, 0x00, 0x00 }, // ASCII 44 (0x2C)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 45 (0x2D)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 46 (0x2E)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00, 0x00, 0x00 }, // ASCII 47 (0x2F)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x6C, 0xC6, 0xC6, 0xD6, 0xD6, 0xC6, 0xC6, 0x6C, 0x38, 0x00, 0x00, 0x00 }, // ASCII 48 (0x30)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x38, 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00, 0x00, 0x00 }, // ASCII 49 (0x31)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 50 (0x32)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x06, 0x06, 0x3C, 0x06, 0x06, 0x06, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 51 (0x33)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x1C, 0x3C, 0x6C, 0xCC, 0xFE, 0x0C, 0x0C, 0x0C, 0x1E, 0x00, 0x00, 0x00 }, // ASCII 52 (0x34)
    [_]u8{ 0x00, 0x00, 0x00, 0xFE, 0xC0, 0xC0, 0xC0, 0xFC, 0x06, 0x06, 0x06, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 53 (0x35)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x60, 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 54 (0x36)
    [_]u8{ 0x00, 0x00, 0x00, 0xFE, 0xC6, 0x06, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x30, 0x00, 0x00, 0x00 }, // ASCII 55 (0x37)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 56 (0x38)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x06, 0x06, 0x0C, 0x78, 0x00, 0x00, 0x00 }, // ASCII 57 (0x39)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 }, // ASCII 58 (0x3A)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00 }, // ASCII 59 (0x3B)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x00, 0x00, 0x00 }, // ASCII 60 (0x3C)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 61 (0x3D)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x00 }, // ASCII 62 (0x3E)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x0C, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 63 (0x3F)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xDE, 0xDE, 0xDE, 0xDC, 0xC0, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 64 (0x40)
    [_]u8{ 0x00, 0x00, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 65 (0x41)
    [_]u8{ 0x00, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x66, 0x66, 0xFC, 0x00, 0x00, 0x00 }, // ASCII 66 (0x42)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xC0, 0xC0, 0xC2, 0x66, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 67 (0x43)
    [_]u8{ 0x00, 0x00, 0x00, 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00, 0x00, 0x00 }, // ASCII 68 (0x44)
    [_]u8{ 0x00, 0x00, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 69 (0x45)
    [_]u8{ 0x00, 0x00, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 70 (0x46)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xDE, 0xC6, 0xC6, 0x66, 0x3A, 0x00, 0x00, 0x00 }, // ASCII 71 (0x47)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 72 (0x48)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 73 (0x49)
    [_]u8{ 0x00, 0x00, 0x00, 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xCC, 0xCC, 0xCC, 0x78, 0x00, 0x00, 0x00 }, // ASCII 74 (0x4A)
    [_]u8{ 0x00, 0x00, 0x00, 0xE6, 0x66, 0x66, 0x6C, 0x78, 0x78, 0x6C, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 75 (0x4B)
    [_]u8{ 0x00, 0x00, 0x00, 0xF0, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 76 (0x4C)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xEE, 0xFE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 77 (0x4D)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xE6, 0xF6, 0xFE, 0xDE, 0xCE, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 78 (0x4E)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 79 (0x4F)
    [_]u8{ 0x00, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 80 (0x50)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xD6, 0xDE, 0x7C, 0x0C, 0x0E, 0x00 }, // ASCII 81 (0x51)
    [_]u8{ 0x00, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 82 (0x52)
    [_]u8{ 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0x06, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 83 (0x53)
    [_]u8{ 0x00, 0x00, 0x00, 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 84 (0x54)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 85 (0x55)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0x00, 0x00, 0x00 }, // ASCII 86 (0x56)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xD6, 0xD6, 0xD6, 0xFE, 0xEE, 0x6C, 0x00, 0x00, 0x00 }, // ASCII 87 (0x57)
    [_]u8{ 0x00, 0x00, 0x00, 0xC6, 0xC6, 0x6C, 0x7C, 0x38, 0x38, 0x7C, 0x6C, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 88 (0x58)
    [_]u8{ 0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 89 (0x59)
    [_]u8{ 0x00, 0x00, 0x00, 0xFE, 0xC6, 0x86, 0x0C, 0x18, 0x30, 0x60, 0xC2, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 90 (0x5A)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 91 (0x5B)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x80, 0xC0, 0xE0, 0x70, 0x38, 0x1C, 0x0E, 0x06, 0x02, 0x00, 0x00, 0x00 }, // ASCII 92 (0x5C)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 93 (0x5D)
    [_]u8{ 0x00, 0x10, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 94 (0x5E)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00 }, // ASCII 95 (0x5F)
    [_]u8{ 0x00, 0x30, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 96 (0x60)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 97 (0x61)
    [_]u8{ 0x00, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x78, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 98 (0x62)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 99 (0x63)
    [_]u8{ 0x00, 0x00, 0x00, 0x1C, 0x0C, 0x0C, 0x3C, 0x6C, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 100 (0x64)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 101 (0x65)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x6C, 0x64, 0x60, 0xF0, 0x60, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 102 (0x66)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x7C, 0x0C, 0xCC, 0x78 }, // ASCII 103 (0x67)
    [_]u8{ 0x00, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x6C, 0x76, 0x66, 0x66, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 104 (0x68)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 105 (0x69)
    [_]u8{ 0x00, 0x00, 0x00, 0x06, 0x06, 0x00, 0x0E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x66, 0x66, 0x3C }, // ASCII 106 (0x6A)
    [_]u8{ 0x00, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x66, 0x6C, 0x78, 0x78, 0x6C, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 107 (0x6B)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 108 (0x6C)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xD6, 0xD6, 0xD6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 109 (0x6D)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00 }, // ASCII 110 (0x6E)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 111 (0x6F)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0 }, // ASCII 112 (0x70)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x7C, 0x0C, 0x0C, 0x1E }, // ASCII 113 (0x71)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x76, 0x66, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 114 (0x72)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 115 (0x73)
    [_]u8{ 0x00, 0x00, 0x00, 0x10, 0x30, 0x30, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1C, 0x00, 0x00, 0x00 }, // ASCII 116 (0x74)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 117 (0x75)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x00, 0x00, 0x00 }, // ASCII 118 (0x76)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xD6, 0xD6, 0xD6, 0xFE, 0x6C, 0x00, 0x00, 0x00 }, // ASCII 119 (0x77)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x38, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 120 (0x78)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x0C, 0xF8 }, // ASCII 121 (0x79)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xCC, 0x18, 0x30, 0x60, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 122 (0x7A)
    [_]u8{ 0x00, 0x00, 0x00, 0x0E, 0x18, 0x18, 0x18, 0x70, 0x18, 0x18, 0x18, 0x18, 0x0E, 0x00, 0x00, 0x00 }, // ASCII 123 (0x7B)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 124 (0x7C)
    [_]u8{ 0x00, 0x00, 0x00, 0x70, 0x18, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x18, 0x18, 0x70, 0x00, 0x00, 0x00 }, // ASCII 125 (0x7D)
    [_]u8{ 0x00, 0x00, 0x00, 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 126 (0x7E)
    [_]u8{ 0x00, 0x00, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0x0C, 0x18, 0x0E }, // ASCII 127 (0x7F)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xC0, 0xC0, 0xC2, 0x66, 0x3C, 0x18, 0x0C, 0x38 }, // ASCII 128 (0x80)
    [_]u8{ 0x00, 0x00, 0x00, 0xCC, 0xCC, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 129 (0x81)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 130 (0x82)
    [_]u8{ 0x00, 0x00, 0x10, 0x38, 0x6C, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 131 (0x83)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x6C, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 132 (0x84)
    [_]u8{ 0x00, 0x00, 0x00, 0x60, 0x30, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 133 (0x85)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x0C, 0x18, 0x0E }, // ASCII 134 (0x86)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x18, 0x0C, 0x38 }, // ASCII 135 (0x87)
    [_]u8{ 0x00, 0x00, 0x10, 0x38, 0x6C, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 136 (0x88)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x6C, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 137 (0x89)
    [_]u8{ 0x00, 0x00, 0x00, 0x60, 0x30, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 138 (0x8A)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xC0, 0xC2, 0x66, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 139 (0x8B)
    [_]u8{ 0x00, 0x00, 0x10, 0x38, 0x6C, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 140 (0x8C)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 141 (0x8D)
    [_]u8{ 0x00, 0x6C, 0x6C, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 142 (0x8E)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xC0, 0xC2, 0x66, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 143 (0x8F)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 144 (0x90)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 145 (0x91)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00, 0x00, 0x00 }, // ASCII 146 (0x92)
    [_]u8{ 0x00, 0x00, 0x10, 0x38, 0x6C, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 147 (0x93)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x6C, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 148 (0x94)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x0C, 0x0C, 0x3C, 0x6C, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 149 (0x95)
    [_]u8{ 0x00, 0x00, 0x00, 0xF8, 0x6C, 0x66, 0x66, 0xF6, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00, 0x00, 0x00 }, // ASCII 150 (0x96)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x3E, 0x0C, 0x3C, 0x6C, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 151 (0x97)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x18, 0x30, 0x1C }, // ASCII 152 (0x98)
    [_]u8{ 0x00, 0x6C, 0x6C, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 153 (0x99)
    [_]u8{ 0x00, 0x6C, 0x6C, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 154 (0x9A)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x30, 0x60, 0x38 }, // ASCII 155 (0x9B)
    [_]u8{ 0x00, 0x00, 0x38, 0x6C, 0x64, 0x60, 0xF0, 0x60, 0x60, 0x60, 0x60, 0xE6, 0xFC, 0x00, 0x00, 0x00 }, // ASCII 156 (0x9C)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 157 (0x9D)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 158 (0x9E)
    [_]u8{ 0x00, 0x18, 0x30, 0x00, 0xF0, 0x60, 0x60, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 159 (0x9F)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x30, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 160 (0xA0)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 161 (0xA1)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 162 (0xA2)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x30, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 163 (0xA3)
    [_]u8{ 0x00, 0x00, 0x00, 0x76, 0xDC, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00 }, // ASCII 164 (0xA4)
    [_]u8{ 0x00, 0x76, 0xDC, 0x00, 0xC6, 0xE6, 0xF6, 0xFE, 0xDE, 0xCE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 165 (0xA5)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 166 (0xA6)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xF0, 0x60, 0x60, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 167 (0xA7)
    [_]u8{ 0x00, 0x00, 0x00, 0x30, 0x30, 0x00, 0x30, 0x30, 0x60, 0xC0, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 168 (0xA8)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 169 (0xA9)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x06, 0x06, 0x06, 0x06, 0x00, 0x00, 0x00, 0x00 }, // ASCII 170 (0xAA)
    [_]u8{ 0x00, 0x00, 0x00, 0xF0, 0x60, 0x60, 0x60, 0x78, 0xE0, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 171 (0xAB)
    [_]u8{ 0x00, 0x00, 0x00, 0x38, 0x18, 0x18, 0x18, 0x1E, 0x78, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 172 (0xAC)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x3C, 0x3C, 0x3C, 0x18, 0x00, 0x00, 0x00 }, // ASCII 173 (0xAD)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x36, 0x6C, 0xD8, 0x6C, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 174 (0xAE)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD8, 0x6C, 0x36, 0x6C, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 175 (0xAF)
    [_]u8{ 0x00, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11, 0x44, 0x11 }, // ASCII 176 (0xB0)
    [_]u8{ 0x44, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 }, // ASCII 177 (0xB1)
    [_]u8{ 0xAA, 0x0C, 0x18, 0x00, 0xC6, 0xE6, 0xF6, 0xFE, 0xDE, 0xCE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 178 (0xB2)
    [_]u8{ 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 179 (0xB3)
    [_]u8{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xF8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 180 (0xB4)
    [_]u8{ 0x18, 0x00, 0x00, 0x0C, 0x18, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00 }, // ASCII 181 (0xB5)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xC6, 0xE6, 0xF6, 0xFE, 0xDE, 0xCE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 182 (0xB6)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00 }, // ASCII 183 (0xB7)
    [_]u8{ 0x00, 0x66, 0xCC, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 184 (0xB8)
    [_]u8{ 0x00, 0x00, 0x00, 0x66, 0xCC, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 185 (0xB9)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 186 (0xBA)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0xDC, 0x76, 0x66, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 187 (0xBB)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00 }, // ASCII 188 (0xBC)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0xDC, 0x76, 0x66, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00 }, // ASCII 189 (0xBD)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 190 (0xBE)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 191 (0xBF)
    [_]u8{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 192 (0xC0)
    [_]u8{ 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 193 (0xC1)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 194 (0xC2)
    [_]u8{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1F, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 195 (0xC3)
    [_]u8{ 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 196 (0xC4)
    [_]u8{ 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xFF, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 197 (0xC5)
    [_]u8{ 0x18, 0x00, 0x00, 0x0C, 0x18, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 198 (0xC6)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0xC6, 0x7C, 0x18, 0x0C, 0x38 }, // ASCII 199 (0xC7)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x18, 0x0C, 0x38 }, // ASCII 200 (0xC8)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 201 (0xC9)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 202 (0xCA)
    [_]u8{ 0x00, 0x00, 0x00, 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x18, 0x0C, 0x38 }, // ASCII 203 (0xCB)
    [_]u8{ 0x00, 0x00, 0x00, 0x10, 0x30, 0x30, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1C, 0x18, 0x0C, 0x38 }, // ASCII 204 (0xCC)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00 }, // ASCII 205 (0xCD)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0x10, 0x30, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1C, 0x00, 0x00, 0x00 }, // ASCII 206 (0xCE)
    [_]u8{ 0x00, 0x38, 0x6C, 0x38, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 207 (0xCF)
    [_]u8{ 0x00, 0x00, 0x38, 0x6C, 0x38, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 208 (0xD0)
    [_]u8{ 0x00, 0x66, 0xCC, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00 }, // ASCII 209 (0xD1)
    [_]u8{ 0x00, 0x00, 0x00, 0x66, 0xCC, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00 }, // ASCII 210 (0xD2)
    [_]u8{ 0x00, 0x0C, 0x18, 0x00, 0xFE, 0xC6, 0x8C, 0x18, 0x30, 0x60, 0xC2, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 211 (0xD3)
    [_]u8{ 0x00, 0x00, 0x00, 0x0C, 0x18, 0x00, 0xFE, 0xCC, 0x18, 0x30, 0x60, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 212 (0xD4)
    [_]u8{ 0x00, 0x18, 0x18, 0x00, 0xFE, 0xC6, 0x8C, 0x18, 0x30, 0x60, 0xC2, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 213 (0xD5)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0xFE, 0xCC, 0x18, 0x30, 0x60, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 214 (0xD6)
    [_]u8{ 0x00, 0x6C, 0x38, 0x10, 0xFE, 0xC6, 0x8C, 0x18, 0x30, 0x60, 0xC2, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 215 (0xD7)
    [_]u8{ 0x00, 0x00, 0x6C, 0x38, 0x10, 0x00, 0xFE, 0xCC, 0x18, 0x30, 0x60, 0xC6, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 216 (0xD8)
    [_]u8{ 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 217 (0xD9)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // ASCII 218 (0xDA)
    [_]u8{ 0x18, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, // ASCII 219 (0xDB)
    [_]u8{ 0xFF, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0x06, 0xC6, 0xC6, 0x7C, 0x00, 0x18, 0x18 }, // ASCII 220 (0xDC)
    [_]u8{ 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x18, 0x18 }, // ASCII 221 (0xDD)
    [_]u8{ 0x30, 0x00, 0x00, 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x18, 0x18 }, // ASCII 222 (0xDE)
    [_]u8{ 0x30, 0x00, 0x00, 0x10, 0x30, 0x30, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1C, 0x00, 0x18, 0x18 }, // ASCII 223 (0xDF)
    [_]u8{ 0x30, 0x00, 0x6C, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 224 (0xE0)
    [_]u8{ 0x00, 0x00, 0x00, 0x3C, 0x66, 0x66, 0x66, 0x6C, 0x66, 0x66, 0x66, 0x66, 0xEC, 0x00, 0x00, 0x00 }, // ASCII 225 (0xE1)
    [_]u8{ 0x00, 0x00, 0x00, 0x6C, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 226 (0xE2)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x6C, 0x6C, 0x6C, 0x6C, 0x6C, 0x66, 0x00, 0x00, 0x00 }, // ASCII 227 (0xE3)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 228 (0xE4)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x30, 0x1C }, // ASCII 229 (0xE5)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xF6, 0xC0, 0xC0, 0xC0 }, // ASCII 230 (0xE6)
    [_]u8{ 0x00, 0x00, 0x00, 0x66, 0xCC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 231 (0xE7)
    [_]u8{ 0x00, 0x00, 0x18, 0x30, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 232 (0xE8)
    [_]u8{ 0x00, 0x00, 0x18, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 233 (0xE9)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x30, 0x00 }, // ASCII 234 (0xEA)
    [_]u8{ 0x00, 0x00, 0x66, 0xCC, 0xCC, 0xCC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 235 (0xEB)
    [_]u8{ 0x00, 0x00, 0x66, 0x66, 0x66, 0xCC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 236 (0xEC)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x66, 0x66, 0x66, 0xCC, 0x00 }, // ASCII 237 (0xED)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 238 (0xEE)
    [_]u8{ 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00 }, // ASCII 239 (0xEF)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0xC0, 0xC6, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x36, 0x36, 0x00, 0x00, 0x00 }, // ASCII 240 (0xF0)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00 }, // ASCII 241 (0xF1)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0x38, 0x0E, 0x38, 0xE0, 0x00, 0xFE, 0x00, 0x00, 0x00, 0x00 }, // ASCII 242 (0xF2)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0E, 0x38, 0xE0, 0x38, 0x0E, 0x00, 0xFE, 0x00, 0x00, 0x00, 0x00 }, // ASCII 243 (0xF3)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00 }, // ASCII 244 (0xF4)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00 }, // ASCII 245 (0xF5)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x7E, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 }, // ASCII 246 (0xF6)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xDC, 0x00, 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 247 (0xF7)
    [_]u8{ 0x00, 0x00, 0x38, 0x6C, 0x6C, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 248 (0xF8)
    [_]u8{ 0x00, 0x00, 0x00, 0x1C, 0x36, 0x60, 0xFC, 0x60, 0xF8, 0x60, 0x60, 0x36, 0x1C, 0x00, 0x00, 0x00 }, // ASCII 249 (0xF9)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ASCII 250 (0xFA)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x04, 0x08, 0x7E, 0x08, 0x10, 0x7E, 0x10, 0x20, 0x00, 0x00, 0x00, 0x00 }, // ASCII 251 (0xFB)
    [_]u8{ 0x00, 0x60, 0x30, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00 }, // ASCII 252 (0xFC)
    [_]u8{ 0x00, 0x30, 0x18, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 253 (0xFD)
    [_]u8{ 0x00, 0x00, 0x00, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 254 (0xFE)
    [_]u8{ 0x00, 0x10, 0x38, 0x44, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00 }, // ASCII 255 (0xFF)
};
