const std = @import("std");
const krn = @import("kernel");

pub const NCCS: usize = 19;

pub const Termios = extern struct {
    c_iflag: IFlag,
    c_oflag: OFlag,
    c_cflag: u32,
    c_lflag: LFlag,
    c_line: u8,
    c_cc: [NCCS]u8,

    pub fn init() Termios {
        return .{
            .c_iflag = IFlag.init(),
            .c_oflag = OFlag.init(),
            .c_cflag = 0,
            .c_lflag = LFlag.init(),
            .c_line = 0,
            .c_cc = [_]u8{0} ** NCCS
        };
    }

    pub fn printDiff(self: *const Termios, other: *const Termios) void {
        krn.logger.DEBUG("Termios diff:", .{});
        if (self.c_iflag != other.c_iflag) {
            inline for (std.meta.fields(IFlag)) |field| {
                const curr_val = @field(self.c_iflag, field.name);
                const new_val = @field(other.c_iflag, field.name);
                if (curr_val != new_val) {
                    krn.logger.DEBUG(
                        "  iflag.{s:<8} {} => {}", 
                        .{field.name, curr_val, new_val}
                    );
                }
            }
        }
        if (self.c_oflag != other.c_oflag) {
            inline for (std.meta.fields(OFlag)) |field| {
                const curr_val = @field(self.c_oflag, field.name);
                const new_val = @field(other.c_oflag, field.name);
                if (curr_val != new_val) {
                    krn.logger.DEBUG(
                        "  oflag.{s:<8} {} => {}", 
                        .{field.name, curr_val, new_val}
                    );
                }
            }
        }
        if (self.c_lflag != other.c_lflag) {
            inline for (std.meta.fields(LFlag)) |field| {
                const curr_val = @field(self.c_lflag, field.name);
                const new_val = @field(other.c_lflag, field.name);
                if (curr_val != new_val) {
                    krn.logger.DEBUG(
                        "  lflag.{s:<8} {} => {}",
                        .{field.name, curr_val, new_val}
                    );
                }
            }
        }
        if (self.c_cflag != other.c_cflag) {
            krn.logger.DEBUG(
                "  cflag 0x{x} => 0x{x}",
                .{self.c_cflag, other.c_cflag}
            );
        }
        if (self.c_line != other.c_line) {
            krn.logger.DEBUG(
                "  c_line 0x{x} => 0x{x}",
                .{self.c_line, other.c_line}
            );
        }
        for (0..NCCS) |i| {
            if (self.c_cc[i] != other.c_cc[i]) {
                krn.logger.DEBUG(
                    "  c_cc[{t}] 0x{x} => 0x{x}",
                    .{
                        @as(CCIdx, @enumFromInt(i)),
                        self.c_cc[i], other.c_cc[i]
                    }
                );
            }
        }
    }
};

// c_cc indexes
pub const VINTR: usize = 0;
pub const VQUIT: usize = 1;
pub const VERASE: usize = 2;
pub const VKILL: usize = 3;
pub const VEOF: usize = 4;
pub const VTIME: usize = 5;
pub const VMIN: usize = 6;
pub const VSWTC: usize = 7;
pub const VSTART: usize = 8;
pub const VSTOP: usize = 9;
pub const VSUSP: usize = 10;
pub const VEOL: usize = 11;
pub const VREPRINT: usize = 12;
pub const VDISCARD: usize = 13;
pub const VWERASE: usize = 14;
pub const VLNEXT: usize = 15;
pub const VEOL2: usize = 16;

const CCIdx = enum(u8) {
    VINTR = 0,
    VQUIT = 1,
    VERASE = 2,
    VKILL = 3,
    VEOF = 4,
    VTIME = 5,
    VMIN = 6,
    VSWTC = 7,
    VSTART = 8,
    VSTOP = 9,
    VSUSP = 10,
    VEOL = 11,
    VREPRINT = 12,
    VDISCARD = 13,
    VWERASE = 14,
    VLNEXT = 15,
    VEOL2 = 16,
};

pub const IFlag = packed struct {
    IGNBRK: bool = false,
    BRKINT: bool = false,
    IGNPAR: bool = false,
    PARMRK: bool = false,
    INPCK: bool = false,
    ISTRIP: bool = false,
    INLCR: bool = false,
    IGNCR: bool = false,
    ICRNL: bool = false,
    IUCLC: bool = false,
    IXON: bool = false,
    IXANY: bool = false,
    IXOFF: bool = false,
    IMAXBEL: bool = false,
    IUTF8: bool = false,
    _padding_1: u17 = 0,

    pub fn init() IFlag {
        return IFlag{};
    }
};

pub const OFlag = packed struct {
    OPOST: bool = false,
    OLCUC: bool = false,
    ONLCR: bool = false,
    OCRNL: bool = false,
    ONOCR: bool = false,
    ONLRET: bool = false,
    OFILL: bool = false,
    ODEL: bool = false,
    NLDLY: bool = false,
    CR1: bool = false,
    CR2: bool = false,
    TAB1: bool = false,
    TAB2: bool = false,
    BSDLY: bool = false,
    VTDLY: bool = false,
    FFDLY: bool = false,
    _padding_1: u16 = 0,

    pub fn init() OFlag {
        return OFlag{};
    }
};

pub const LFlag = packed struct {
    ISIG: bool = false,
    ICANON: bool = false,
    XCASE: bool = false,
    ECHO: bool = false,
    ECHOE: bool = false,
    ECHOK: bool = false,
    ECHONL: bool = false,
    NOFLSH: bool = false,
    TOSTOP: bool = false,
    ECHOCTL: bool = false,
    ECHOPRT: bool = false,
    ECHOKE: bool = false,
    FLUSHO: bool = false,
    _unused_1: bool = false,
    PENDIN: bool = false,
    IEXTEN: bool = false,
    EXTPROC: bool = false,
    _padding_2: u15 = 0,

    pub fn init() LFlag {
        return LFlag{};
    }
};
