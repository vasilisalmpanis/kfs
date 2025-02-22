const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;
const dbg = @import("debug");

pub const Img = struct {
    width: u32,
    height: u32,
    data: [] const u32,
};

pub const Font = struct {
    width: u8,
    height: u8,
    data: [256][]const u16
};

pub const FrameBuffer = struct {
    fb_info: multiboot.FramebufferInfo,
    fb_ptr: [*]u32,
    cwidth: u32,
    cheight: u32,
    virtual_buffer: [*]u32,
    font: *const Font,

    pub fn init(
        boot_info: *multiboot.multiboot_info,
        font: *const Font
    ) FrameBuffer {
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
            .cwidth = (fb_info.?.pitch / 4) / font.width,
            .cheight = fb_info.?.height / font.height,
            .virtual_buffer = @ptrFromInt(mm.kmalloc(fb_info.?.width * fb_info.?.height * @sizeOf(u32))),
            .font = font,
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
        const char_data = self.font.data[c];
        const x = cx * self.font.width;
        const y = cy * self.font.height;
        for (0..self.font.height) |row| {
            for (0..self.font.width) |bit| {
                const b: u4 = @intCast(bit);
                const one: u16 = 1;
                const offset: u4 = @intCast(self.font.width - 1);
                const mask: u16 = one << (offset - b);
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
        const x = cx * self.font.width;
        const y = cy * self.font.height;
        for (0..self.font.width) |pos| {
            self.virtual_buffer[(y + self.font.height - 2) * (self.fb_info.pitch / 4) + x + pos] = fg;
            self.virtual_buffer[(y + self.font.height - 1) * (self.fb_info.pitch / 4) + x + pos] = fg;
        }
    }

    pub fn putPixel(
        self: *FrameBuffer,
        x: u32, 
        y: u32,
        clr: u32
    ) void {
        if (x >= self.fb_info.width)
            return ;
        if (y >= self.fb_info.height)
            return ;
        self.virtual_buffer[y * (self.fb_info.pitch / 4) + x] = clr;
    }

    pub fn fillColor(
        self: *FrameBuffer,
        clr: u32
    ) void {
        @memset(
            self.virtual_buffer[0..self.fb_ptr.width * self.fb_ptr.height],
            clr
        );
    }

    pub fn putImg(
        self: *FrameBuffer,
        x: u32, 
        y: u32,
        img: *const Img
    ) void {
        if (x >= self.fb_info.width)
            return ;
        if (y >= self.fb_info.height)
            return ;
        const max_dx = if (x + img.width < self.fb_info.width) img.width
            else self.fb_info.width - x;
        var row: u32 = 0;
        while (row < img.height and y + row < self.fb_info.height): (row += 1) {
            const buf_pos = (y + row) * (self.fb_info.pitch / 4) + x;
            const img_pos = row * img.width;
            @memcpy(
                self.virtual_buffer[buf_pos..buf_pos + max_dx],
                img.data[img_pos..img_pos + max_dx]
            );
        }

    }
};
