const std = @import("std");
const printf = @import("./printf.zig").printf;
const multiboot = @import("arch").multiboot;
const tsk = @import("kernel").task;
const TTY = @import("drivers").tty.TTY;
const ConsoleColors = @import("drivers").tty.ConsoleColors;
const krn = @import("kernel");

const os_logo = [_][]const u8{
    "  _  _    ___  ",
    " | || |  |__ \\ ",
    " | || |_    ) |",
    " |__   _|  / / ",
    "    | |   / /_ ",
    "    |_|  |____|",
    "               ",
};

const logo_color = @intFromEnum(ConsoleColors.Cyan);
const header_color = @intFromEnum(ConsoleColors.LightBlue);
const value_color = @intFromEnum(ConsoleColors.White);
const separator_color = @intFromEnum(ConsoleColors.DarkGray);

fn formatMemorySize(bytes: u64, buffer: []u8) []u8 {
    if (bytes < 1024) {
        const len = std.fmt.formatIntBuf(
            buffer,
            bytes,
            10,
            .lower,
            .{}
        );
        buffer[len] = ' ';
        buffer[len+1] = 'B';
        return buffer[0..len+2];
    } else if (bytes < 1024 * 1024) {
        const kb = @divFloor(bytes, 1024);
        const len = std.fmt.formatIntBuf(
            buffer, 
            kb, 
            10, 
            .lower, 
            .{}
        );
        buffer[len] = ' ';
        buffer[len+1] = 'K';
        buffer[len+2] = 'B';
        return buffer[0..len+3];
    } else {
        const mb = @divFloor(bytes, 1024 * 1024);
        const len = std.fmt.formatIntBuf(
            buffer, 
            mb, 
            10, 
            .lower, 
            .{}
        );
        buffer[len] = ' ';
        buffer[len+1] = 'M';
        buffer[len+2] = 'B';
        return buffer[0..len+3];
    }
}

pub fn neofetch(tty: *TTY, boot_info: *multiboot.MultibootInfo1) void {
    const original_fg = tty._fg_colour;
    
    const total_mem_kb = boot_info.mem_lower + boot_info.mem_upper;
    const total_mem = total_mem_kb * 1024;
    
    const fb_info = multiboot.getFBInfo(boot_info) orelse {
        printf("Error: Framebuffer info not available\n", .{});
        return;
    };
    
    var available_mem: u64 = 0;
    var i: u32 = 0;
    while (i < boot_info.mmap_length) : (i += @sizeOf(multiboot.MultibootMemoryMap)) {
        const mmap: *multiboot.MultibootMemoryMap = @ptrFromInt(boot_info.mmap_addr + i + krn.mm.PAGE_OFFSET);
        if (mmap.type == 1) {
            available_mem += mmap.len[0];
        }
    }
    
    var task_count: u32 = 0;
    var it = tsk.initial_task.list.iterator();
    while (it.next()) |_| {
        task_count += 1;
    }
    
    const uptime_seconds = krn.getSecondsFromStart();
    const uptime_hours = uptime_seconds / 3600;
    const uptime_minutes = (uptime_seconds % 3600) / 60;
    const uptime_secs = uptime_seconds % 60;
    
    const os_name = "KFS";
    const kernel_version = "0.0.1";
    
    var buffer: [32]u8 = undefined;
    
    var max_logo_width: usize = 0;
    for (os_logo) |line| {
        max_logo_width = @max(max_logo_width, line.len);
    }
    
    const info_start_x = max_logo_width + 4;
    
    printf("\n", .{});
    
    const info_lines: u32 = 9;
    const logo_lines = os_logo.len;
    const total_lines = @max(info_lines, logo_lines);
    
    var line: u32 = 0;
    while (line < total_lines) : (line += 1) {        
        if (line < logo_lines) {
            tty.setColor(logo_color);
            printf("{s}", .{os_logo[line]});
            
            const padding = info_start_x - os_logo[line].len - 2;
            for (0..padding) |_| {
                printf(" ", .{});
            }
        } else {
            for (0..info_start_x - 2) |_| {
                printf(" ", .{});
            }
        }
        
        switch (line) {
            0 => {
                tty.setColor(header_color);
                printf("OS: ", .{});
                tty.setColor(value_color);
                printf(os_name, .{});
            },
            1 => {
                tty.setColor(header_color);
                printf("Kernel: ", .{});
                tty.setColor(value_color);
                printf(kernel_version, .{});
            },
            2 => {
                tty.setColor(header_color);
                printf("Uptime: ", .{});
                tty.setColor(value_color);
                printf("{d}h {d}m {d}s", .{uptime_hours, uptime_minutes, uptime_secs});
            },
            3 => {
                tty.setColor(header_color);
                printf("Memory: ", .{});
                tty.setColor(value_color);
                
                var mem_str = formatMemorySize(available_mem, buffer[0..]);
                printf("{s} / ", .{mem_str});
                
                mem_str = formatMemorySize(total_mem, buffer[0..]);
                printf("{s}", .{mem_str});
            },
            4 => {
                tty.setColor(header_color);
                printf("Resolution: ", .{});
                tty.setColor(value_color);
                printf("{d}x{d} @ {d}bpp", .{fb_info.width, fb_info.height, 32});
            },
            5 => {
                tty.setColor(header_color);
                printf("Tasks: ", .{});
                tty.setColor(value_color);
                printf("{d} running", .{task_count});
            },
            6 => {
                tty.setColor(header_color);
                printf("Terminal: ", .{});
                tty.setColor(value_color);
                printf("{d}x{d} chars", .{tty.width, tty.height});
            },
            7 => {
                tty.setColor(header_color);
                printf("CPU: ", .{});
                tty.setColor(value_color);
                printf("{s}", .{getCpuInfo()});
            },
            8 => {
                for (0..8) |color_idx| {
                    const color = getColorByIndex(color_idx);
                    tty.setColor(color);
                    printf("##", .{});
                    tty.setColor(value_color);
                    printf(" ", .{});
                }
            },
            else => {},
        }
        
        printf("\n", .{});
    }
    tty.setColor(original_fg);
}

fn getCpuInfo() []const u8 {
    return "Some CPU @ 1.0 GHz";
}

fn getColorByIndex(index: usize) u32 {
    const colors = [_]u32{
        @intFromEnum(ConsoleColors.Black),
        @intFromEnum(ConsoleColors.Red),
        @intFromEnum(ConsoleColors.Green),
        @intFromEnum(ConsoleColors.Brown),
        @intFromEnum(ConsoleColors.Blue),
        @intFromEnum(ConsoleColors.Magenta),
        @intFromEnum(ConsoleColors.Cyan),
        @intFromEnum(ConsoleColors.White),
    };
    
    return if (index < colors.len) colors[index] else colors[0];
}
