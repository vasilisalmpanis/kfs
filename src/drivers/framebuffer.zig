const multiboot = @import("arch").multiboot;
const mm = @import("kernel").mm;
const dbg = @import("debug");
const krn = @import("kernel");

pub var render_queue = krn.wq.WaitQueueHead.init();

pub fn render_thread(_: ?*const anyopaque) i32 {
    while (!krn.task.current.should_stop) {
        krn.serial.print("here\n");
        krn.screen.framebuffer.render();
        render_queue.wait(false, 0);
    }
    return 0;
}

pub const Img = struct {
    width: usize,
    height: usize,
    data: [] const usize,
};

pub const Font = struct {
    width: u8,
    height: u8,
    data: [256][]const u16
};

pub const ScrollDirection = enum {
    up,
    down,
};

/// Rendering mode for the framebuffer
pub const RenderMode = enum {
    /// Double-buffered: render to virtual_buffer, then copy to fb_ptr on render()
    /// Pro: No tearing. Con: Extra memory copy.
    /// Preffered for graphical use-cases.
    double_buffered,
    /// Zero-copy: render directly to fb_ptr, no virtual_buffer allocated
    /// Pro: Faster, less memory. Con: May have tearing during updates.
    /// Preffered for terminal use-cases.
    zero_copy,
};

pub const DirtyRect = struct {
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,

    pub fn init(x1: usize, y1: usize, x2: usize, y2: usize) DirtyRect {
        return .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
        };
    }

    pub fn fullScreen(w: usize, h: usize) DirtyRect {
        return .{
            .x1 = 0,
            .y1 = 0,
            .x2 = w - 1,
            .y2 = h - 1,
        };
    }

    pub inline fn merge(self: *DirtyRect, other: DirtyRect) DirtyRect {
        return .{
            .x1 = @min(self.x1, other.x1),
            .y1 = @min(self.y1, other.y1),
            .x2 = @max(self.x2, other.x2),
            .y2 = @max(self.y2, other.y2),
        };
    }
};

pub const FrameBuffer = struct {
    fb_info: *multiboot.TagFrameBufferInfo,
    fb_ptr: [*]volatile u32,
    virt_buffer: ?[*]u32,
    font: *const Font,
    mode: RenderMode,

    // Precomputed values (to avoid repeated computation)
    stride: usize, // pixels per row (pitch / 4)
    width: usize, // screen width in pixels
    height: usize, // screen height in pixels
    total_pixels: usize, // width * height (for clear/scroll)
    cwidth: usize, // screen width in characters
    cheight: usize, // screen height in characters
    cell_w: usize, // font.width
    cell_h: usize, // font.height

    dirty: DirtyRect,
    has_dirty: bool,
    lock: krn.Spinlock,

    pub fn init(
        boot_info: *multiboot.Multiboot,
        font: *const Font,
        mode: RenderMode,
    ) FrameBuffer {
        if (boot_info.getTag(multiboot.TagFrameBufferInfo)) |tag| {
            const fb_size: usize = tag.height * tag.pitch;
            const num_pages = (fb_size + 0xFFF) / mm.PAGE_SIZE;
            var i: usize = 0;
            var addr: usize = @truncate(tag.addr);
            const offset = addr & 0xFFF;
            addr &= ~@as(usize, 0xFFF);
            var virt_addr: usize = mm.virt_memory_manager.findFreeSpace(
                num_pages,
                mm.PAGE_OFFSET,
                0xFFFFF000,
                false
            );
            const first_addr: usize = virt_addr;
            while (i < num_pages) : (i += 1) {
                mm.virt_memory_manager.mapPage(
                    virt_addr,
                    addr,
                    .{ .write_through = true },
                );
                virt_addr += mm.PAGE_SIZE;
                addr += mm.PAGE_SIZE;
            }

            // Precompute all frequently used values
            const cell_w: usize = font.width;
            const cell_h: usize = font.height;
            const stride = tag.pitch / 4;
            const total_pixels = tag.height * stride;
            
            const vbuf: ?[*]u32 = switch (mode) {
                .double_buffered => mm.kmallocArray(u32, total_pixels),
                .zero_copy => null,
            };

            if (mode == .double_buffered and vbuf == null) {
                @panic("out of memory");
            }

            var fb = FrameBuffer{
                .fb_info = tag,
                .fb_ptr = @ptrFromInt(first_addr + offset),
                .virt_buffer = vbuf,
                .font = font,
                .mode = mode,
                .stride = stride,
                .width = tag.width,
                .height = tag.height,
                .total_pixels = total_pixels,
                .cwidth = stride / cell_w,
                .cheight = tag.height / cell_h,
                .cell_w = cell_w,
                .cell_h = cell_h,
                .dirty = DirtyRect.fullScreen(tag.width, tag.height),
                .has_dirty = true,
                .lock = krn.Spinlock.init(),
            };
            fb.clear(0);
            render_queue.setup();
            return fb;
        } else {
            @panic("no framebuffer info provided!");
        }
    }

    inline fn buffer(self: *FrameBuffer) [*]u32 {
        return switch (self.mode) {
            .double_buffered => self.virt_buffer.?,
            .zero_copy => @volatileCast(self.fb_ptr),
        };
    }

    inline fn isBuffered(self: *const FrameBuffer) bool {
        return self.mode == .double_buffered;
    }

    pub fn render(self: *FrameBuffer) void {
        if (!self.isBuffered())
            return;
        if (!self.has_dirty)
            return;
        
        const x1 = @min(self.dirty.x1, self.width -| 1);
        const x2 = @min(self.dirty.x2, self.width -| 1);
        const y1 = @min(self.dirty.y1, self.height -| 1);
        const y2 = @min(self.dirty.y2, self.height -| 1);

        const copy_width = x2 -| x1 + 1;

        var row_offset = y1 * self.stride + x1;

        const lock_state = self.lock.lock_irq_disable();        
        for (y1..y2 + 1) |_| {
            @memcpy(
                self.fb_ptr[row_offset..row_offset + copy_width],
                self.virt_buffer.?[row_offset..row_offset + copy_width],
            );
            row_offset += self.stride;
        }
        self.lock.unlock_irq_enable(lock_state);

        self.dirty = DirtyRect.init(0, 0, 0, 0);
        self.has_dirty = false;
    }

    pub fn markDirtyPixels(
        self: *FrameBuffer,
        x1: usize,
        y1: usize,
        x2: usize,
        y2: usize
    ) void {
        if (!self.isBuffered())
            return;
        const new_dirty = DirtyRect.init(x1, y1, x2, y2);
        if (self.has_dirty) {
            self.dirty = self.dirty.merge(new_dirty);
        } else {
            self.dirty = new_dirty;
            self.has_dirty = true;
        }
    }

    pub inline fn markFullDirty(self: *FrameBuffer) void {
        if (!self.isBuffered())
            return;
        self.dirty = DirtyRect.fullScreen(self.width, self.height);
        self.has_dirty = true;
    }

    pub fn clear(self: *FrameBuffer, bg: u32) void {
        const lock_state = self.lock.lock_irq_disable();
        @memset(self.buffer()[0..self.total_pixels], bg);
        self.lock.unlock_irq_enable(lock_state);
        self.markFullDirty();
    }

    pub fn scrollPixels(
        self: *FrameBuffer,
        pixel_lines: usize,
        direction: ScrollDirection,
        bg: u32
    ) void {
        if (pixel_lines == 0)
            return;
        if (pixel_lines >= self.height) {
            self.clear(bg);
            return;
        }

        const offset = pixel_lines * self.stride;
        const copy_size = self.total_pixels - offset;

        const lock_state = self.lock.lock_irq_disable();
        const buf = self.buffer();

        switch (direction) {
            .up => {
                @memmove(buf[0..copy_size], buf[offset..self.total_pixels]);
                @memset(buf[copy_size..self.total_pixels], bg);
            },
            .down => {
                @memmove(buf[offset..self.total_pixels], buf[0..copy_size]);
                @memset(buf[0..offset], bg);
            },
        }
        self.lock.unlock_irq_enable(lock_state);

        self.markFullDirty();
    }

    pub fn clearChar(self: *FrameBuffer, cx: usize, cy: usize, bg: u32) void {
        const cell_w = self.cell_w;
        const cell_h = self.cell_h;
        const x = cx * cell_w;
        const y = cy * cell_h;
        const stride = self.stride;

        const lock_state = self.lock.lock_irq_disable();
        const buf = self.buffer();

        var pos = y * stride + x;
        for (0..cell_h) |_| {
            @memset(buf[pos..pos + cell_w], bg);
            pos += stride;
        }
        self.lock.unlock_irq_enable(lock_state);

        self.markDirtyPixels(
            x,
            y,
            x + cell_w - 1,
            y + cell_h - 1
        );
    }

    pub fn putchar(
        self: *FrameBuffer,
        c: u8,
        cx: usize,
        cy: usize,
        bg: u32,
        fg: u32,
    ) void {
        if (c == 0)
            return self.clearChar(cx, cy, bg);

        const char_data = self.font.data[c];
        const x = cx * self.cell_w;
        const y = cy * self.cell_h;

        const lock_state = self.lock.lock_irq_disable();
        const buf = self.buffer();

        const color_delta = fg ^ bg;
        var pos = y * self.stride + x;

        for (0..self.cell_h) |row| {
            const row_bits = char_data[row];
            comptime var bit: usize = 0;
            inline while (bit < 16) : (bit += 1) {
                if (bit < self.cell_w) {
                    const shift: u4 = @intCast(15 - bit);
                    const is_set = (row_bits >> shift) & 1;
                    const mask: u32 = @bitCast(-@as(i32, @intCast(is_set)));
                    buf[pos + bit] = bg ^ (color_delta & mask);
                }
            }
            pos += self.stride;
        }
        self.lock.unlock_irq_enable(lock_state);

        self.markDirtyPixels(
            x,
            y,
            x + self.cell_w - 1,
            y + self.cell_h - 1
        );
    }

    pub fn cursor(
        self: *FrameBuffer,
        cx: usize,
        cy: usize,
        fg: u32
    ) void {
        const x = cx * self.cell_w;
        const y = cy * self.cell_h;

        const line1 = (y + self.cell_h - 2) * self.stride + x;
        const line2 = line1 + self.stride;

        const lock_state = self.lock.lock_irq_disable();
        const buf = self.buffer();
        @memset(buf[line1..line1 + self.cell_w], fg);
        @memset(buf[line2..line2 + self.cell_w], fg);
        self.lock.unlock_irq_enable(lock_state);

        self.markDirtyPixels(
            x,
            y + self.cell_h - 2,
            x + self.cell_w - 1,
            y + self.cell_h - 1
        );
    }

    pub fn putPixel(
        self: *FrameBuffer,
        x: usize,
        y: usize,
        clr: u32
    ) void {
        if (x >= self.width or y >= self.height)
            return ;

        const lock_state = self.lock.lock_irq_disable();
        self.buffer()[y * self.stride + x] = clr;
        self.lock.unlock_irq_enable(lock_state);
    
        self.markDirtyPixels(x, y, x, y);
    }

    pub fn fillColor(
        self: *FrameBuffer,
        clr: u32
    ) void {
        const lock_state = self.lock.lock_irq_disable();
        @memset(self.buffer()[0..self.total_pixels], clr);
        self.lock.unlock_irq_enable(lock_state);
        self.markFullDirty();
    }

    pub fn putImg(
        self: *FrameBuffer,
        x: usize,
        y: usize,
        img: *const Img
    ) void {
        if (x >= self.width or y >= self.height)
            return;

        const max_dx = @min(img.width, self.width - x);
        const max_dy = @min(img.height, self.height - y);

        var buf_pos = y * self.stride + x;
        var img_pos: usize = 0;

        const lock_state = self.lock.lock_irq_disable();
        const buf = self.buffer();
        for (0..max_dy) |_| {
            @memcpy(
                buf[buf_pos..buf_pos + max_dx],
                img.data[img_pos..img_pos + max_dx]
            );
            buf_pos += self.stride;
            img_pos += img.width;
        }
        self.lock.unlock_irq_enable(lock_state);

        self.markDirtyPixels(x, y, x + max_dx - 1, y + max_dy - 1);
    }
};
