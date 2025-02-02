const tty = @import("tty-fb.zig");
const fb = @import("./framebuffer.zig");
const multiboot = @import("arch").multiboot;

pub var current_tty: ?*tty.TTY = null;
pub var framebuffer: fb.FrameBuffer = undefined;

pub const Screen = struct {
    tty : [2] tty.TTY = undefined,
    frmb: fb.FrameBuffer,
    
    pub fn init(boot_info: *multiboot.multiboot_info) *Screen {
        const frm = fb.FrameBuffer.init(boot_info);
        var scr = Screen{
            .tty = .{
                tty.TTY.init(
                    frm.cwidth,
                    frm.cheight
                )
            } ** 2,
            .frmb = frm,
        };
        current_tty = &scr.tty[0];
        framebuffer = scr.frmb;
        return &scr;
    }

    pub fn switch_tty(self: *Screen, num: u8) void {
        current_tty = &self.tty[num];
        current_tty.?.render();
    }
};
