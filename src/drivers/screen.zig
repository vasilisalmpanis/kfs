const tty = @import("tty-fb.zig");
const fb = @import("./framebuffer.zig");
const multiboot = @import("arch").multiboot;
const printf = @import("debug").printf;
const fonts = @import("./fonts.zig");

pub var current_tty: ?*tty.TTY = null;
pub var framebuffer: fb.FrameBuffer = undefined;

pub const Screen = struct {
    tty : [10] tty.TTY = undefined,
    frmb: fb.FrameBuffer,
    
    pub fn init(boot_info: *multiboot.multiboot_info) Screen {
        const frm = fb.FrameBuffer.init(boot_info, &fonts.VGA16x32);
        var scr = Screen{
            .frmb = frm,
        };
        for (0..10) |index| {
            scr.tty[index] = tty.TTY.init(frm.cwidth, frm.cheight);
        }
        framebuffer = scr.frmb;
        return scr;
    }

    pub fn switch_tty(self: *Screen, num: u8) void {
        current_tty = &self.tty[num];
        current_tty.?.render();
    }
};
