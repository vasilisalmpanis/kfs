const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;
const dbg = @import("debug");
const krn = @import("kernel");

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
    fb_info: *multiboot.TagFrameBufferInfo,
    fb_ptr: [*]u32,
    cwidth: u32,
    cheight: u32,
    virtual_buffer: [*]u32,
    font: *const Font,

    pub fn init(
        boot_info: *multiboot.Multiboot,
        font: *const Font
    ) FrameBuffer {
        if (boot_info.getTag(multiboot.TagFrameBufferInfo)) |tag| {
            // const fb_info: ?multiboot.FramebufferInfo = multiboot.getFBInfo(boot_info);
            const fb_size: u32 = tag.height * tag.pitch;
            const num_pages = (fb_size + 0xFFF) / mm.PAGE_SIZE;
            var i: u32 = 0;
            var addr: u32 = @truncate(tag.addr);
            addr &= 0xFFFFF000;
            const offset = addr & 0xFFF;
            var virt_addr: u32 = mm.virt_memory_manager.findFreeSpace(
                num_pages,
                mm.PAGE_OFFSET,
                0xFFFFF000,
                false
            );
            const first_addr: u32 = virt_addr;
            while (i < num_pages) : (i += 1) {
                mm.virt_memory_manager.mapPage(virt_addr, addr, .{});
                virt_addr += mm.PAGE_SIZE;
                addr += mm.PAGE_SIZE;
            }
            const buffer: ?[*]u32 = mm.kmallocArray(u32, tag.width * tag.height);
            if (buffer) |_buffer| {
                var fb = FrameBuffer{
                    .fb_info = tag,
                    .fb_ptr = @ptrFromInt(first_addr + offset),
                    .cwidth = (tag.pitch / 4) / font.width,
                    .cheight = tag.height / font.height,
                    .virtual_buffer = _buffer,
                    .font = font,
                };
                fb.clear(0);
                return fb;
            } else {
                @panic("out of memory");
            }
        } else {
            @panic("no framebuffer info provided!");
        }
    }

    pub fn render(self: *FrameBuffer) void {
        const max_index = self.fb_info.height * self.fb_info.width;
        // krn.logger.INFO("HERE", .{});
        @memcpy(self.fb_ptr[0..max_index], self.virtual_buffer[0..max_index]);
        // krn.logger.INFO("NOT HERE", .{});
    }

    pub fn clear(self: *FrameBuffer, bg: u32) void {
        @memset(self.virtual_buffer[0 .. self.fb_info.height * self.fb_info.width], bg);
    }

    fn clearChar(self: *FrameBuffer, cx: u32, cy: u32, bg: u32) void {
        const x = cx * self.font.width;
        const y = cy * self.font.height;
        const width = (self.fb_info.pitch / 4);
        var pos = y * width + x;
        for (0..self.font.height) |_| {
            @memset(self.virtual_buffer[pos..pos + self.font.width], bg);
            pos += width;
        }
    }

    pub fn putchar(
        self: *FrameBuffer,
        c: u8,
        cx: u32,
        cy: u32,
        bg: u32,
        fg: u32,
    ) void {
        if (c == 0) return self.clearChar(cx, cy, bg);
        const char_data = self.font.data[c];
        const x = cx * self.font.width;
        const y = cy * self.font.height;
        const one: u16 = 1;
        const offset: u4 = @intCast(self.font.width - 1);
        const width = (self.fb_info.pitch / 4);
        var pos = y * width + x;
        for (0..self.font.height) |row| {
            for (0..self.font.width) |bit| {
                const mask: u16 = one << (offset - @as(u4, @intCast(bit)));
                if ((char_data[row] & mask) != 0) {
                    self.virtual_buffer[pos + bit] = fg;
                } else {
                    self.virtual_buffer[pos + bit] = bg;
                }
            }
            pos += width;
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
        const width = (self.fb_info.pitch / 4);
        const line1 = (y + self.font.height - 2) * width  + x;
        const line2 = line1 + width;
        @memset(self.virtual_buffer[line1..(line1 + self.font.width)], fg);
        @memset(self.virtual_buffer[line2..(line2 + self.font.width)], fg);
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
