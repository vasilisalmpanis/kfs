const tty = @import("./platform/tty.zig");
const fb = @import("./framebuffer.zig");
const multiboot = @import("arch").multiboot;
const printf = @import("debug").printf;
const fonts = @import("./fonts.zig");
const krn = @import("kernel");

pub var current_tty: ?*tty.TTY = null;
pub var framebuffer: fb.FrameBuffer = undefined;

pub const Screen = struct {
    tty : [1] tty.TTY = undefined,
    frmb: fb.FrameBuffer,
    
    pub fn init(boot_info: *multiboot.Multiboot) Screen {
        const frm = fb.FrameBuffer.init(boot_info, &fonts.VGA16x32);
        const scr = Screen{
            .frmb = frm,
        };
        framebuffer = scr.frmb;
        // for (0..1) |index| {
        //     scr.tty[index] = tty.TTY.init(frm.cwidth, frm.cheight);
        // }
        return scr;
    }

    pub fn switchTTY(self: *Screen, num: u8) void {
        current_tty = &self.tty[num];
        current_tty.?.render();
    }
};

pub fn initScreen(scr: *Screen, boot_info: *multiboot.Multiboot) void {
    scr.* = Screen.init(boot_info);
    current_tty = null;
}
