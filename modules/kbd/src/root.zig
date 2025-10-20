// const std = @import("std");

// pub extern fn kmalloc(size: u32) u32;
//
const types = @import("./types.zig");
const std = @import("std");
pub extern var global_keyboard: *types.drivers.Keyboard;

pub const keymap_us = std.EnumMap(
    types.drivers.keyboard.ScanCode,
    types.drivers.keyboard.KeymapEntry
).init(.{
    .K_ESC          = .{ .normal = 27, .shift = 'a', .ctrl = 'z'},
    .K_1            = .{ .normal = '1', .shift = '!', },
    .K_2            = .{ .normal = '2', .shift = '@', },
    .K_3            = .{ .normal = '3', .shift = '#', },
    .K_4            = .{ .normal = '4', .shift = '$', },
    .K_5            = .{ .normal = '5', .shift = '%', },
    .K_6            = .{ .normal = '6', .shift = '^', .ctrl = 30, },
    .K_7            = .{ .normal = '7', .shift = '&', },
    .K_8            = .{ .normal = '8', .shift = '*', },
    .K_9            = .{ .normal = '9', .shift = '(', },
    .K_0            = .{ .normal = '0', .shift = ')', },
    .K_MINUS        = .{ .normal = '-', .shift = '_', },
    .K_EQUALS       = .{ .normal = '=', .shift = '+', .ctrl = 31, },
    .K_BACKSPACE    = .{ .normal = 8, },
    .K_TAB          = .{ .normal = '\t', },
    .K_Q            = .{ .normal = 'q', .shift = 'Q', .ctrl = 17, }, 
    .K_W            = .{ .normal = 'w', .shift = 'W', .ctrl = 23, }, 
    .K_E            = .{ .normal = 'e', .shift = 'E', .ctrl = 5, }, 
    .K_R            = .{ .normal = 'r', .shift = 'R', .ctrl = 18, }, 
    .K_T            = .{ .normal = 't', .shift = 'T', .ctrl = 20, }, 
    .K_Y            = .{ .normal = 'y', .shift = 'Y', .ctrl = 25, }, 
    .K_U            = .{ .normal = 'u', .shift = 'U', .ctrl = 21, }, 
    .K_I            = .{ .normal = 'i', .shift = 'I', .ctrl = 9, }, 
    .K_O            = .{ .normal = 'o', .shift = 'O', .ctrl = 15, }, 
    .K_P            = .{ .normal = 'p', .shift = 'P', .ctrl = 16, },
    .K_OSQB         = .{ .normal = '[', .shift = '{' }, 
    .K_CSQB         = .{ .normal = ']', .shift = '}' }, 
    .K_ENTER        = .{ .normal = '\n', },

    .K_A            = .{ .normal = 'a', .shift = 'A', .ctrl = 1, },
    .K_S            = .{ .normal = 's', .shift = 'S', .ctrl = 19, },
    .K_D            = .{ .normal = 'd', .shift = 'D', .ctrl = 4, },
    .K_F            = .{ .normal = 'f', .shift = 'F', .ctrl = 6, },
    .K_G            = .{ .normal = 'g', .shift = 'G', .ctrl = 7, },
    .K_H            = .{ .normal = 'h', .shift = 'H', .ctrl = 8, },
    .K_J            = .{ .normal = 'j', .shift = 'J', .ctrl = 10, },
    .K_K            = .{ .normal = 'k', .shift = 'K', .ctrl = 11, },
    .K_L            = .{ .normal = 'l', .shift = 'L', .ctrl = 12, },
    .K_SEMICOL      = .{ .normal = ';', .shift = ':', },
    .K_QUOTE        = .{ .normal = '\'', .shift = '"', },
    .K_BCKQUOTE     = .{ .normal = '`', .shift = '~', },

    
    .K_BCKSL        = .{ .normal = '\\', .shift = '|', .ctrl = 28, }, 
    .K_Z            = .{ .normal = 'z', .shift = 'Z', .ctrl = 26, }, 
    .K_X            = .{ .normal = 'x', .shift = 'X', .ctrl = 24, }, 
    .K_C            = .{ .normal = 'c', .shift = 'C', .ctrl = 3, }, 
    .K_V            = .{ .normal = 'v', .shift = 'V', .ctrl = 22, }, 
    .K_B            = .{ .normal = 'b', .shift = 'B', .ctrl = 2, }, 
    .K_N            = .{ .normal = 'n', .shift = 'N', .ctrl = 14, }, 
    .K_M            = .{ .normal = 'm', .shift = 'M', .ctrl = 13, }, 
    .K_COMMA        = .{ .normal = ',', .shift = '<', }, 
    .K_DOT          = .{ .normal = '.', .shift = '>', }, 
    .K_SLASH        = .{ .normal = '/', .shift = '?', },

    .K_WHITESPACE   = .{ .normal = ' ', },

    .K_KPAD_MINUS   = .{ .normal = '-', },
    .K_KPAD_PLUS    = .{ .normal = '+', },
    .K_KPAD_STAR    = .{ .normal = '*', },

    .K_LLALT        = .{ .normal = '<', .shift = '>', },
});

var mod_kbd: types.drivers.Keyboard = types.drivers.Keyboard{
    .alt = false,
    .shift = false,
    .buffer = .{0} ** 256,
    .caps = false,
    .cntl = false,
    .read_pos = 0,
    .write_pos = 0,
    .keymap = &keymap_us,
};

pub fn outb(port: u16, value: u8) void {
    asm volatile ("outb %al, %dx"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port)
    );
}

pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

extern fn saveScancode(self: *types.drivers.Keyboard, scancode: u8) void;

pub const ISRHandler = anyopaque;
pub extern fn registerHandler(irq_num: u32, handl: * const ISRHandler) void;
pub extern fn print_serial(arr: [*]const u8, size: u32) void;
pub extern fn print_screen(arr: [*]const u8, size: u32) void;
pub var temp: u32 = 2;

pub fn add3(a: u32, b: u32) u32 {
    temp += a + b;
    const slice: []const u8 = "hello world\n";
    print_serial(slice.ptr, slice.len);
    print_screen(slice.ptr, slice.len);
    return temp;
}

pub fn add2(a: u32, b: u32) u32 {
    return add3(a, b);
}

pub fn add(a: u32, b: u32) u32 {
    return add2(a, b);
}

export fn example_init() linksection(".init") callconv(.c) u32 {
    global_keyboard = &mod_kbd;
    return 0;
}

export fn example_exit() linksection(".exit") callconv(.c) void {
}
