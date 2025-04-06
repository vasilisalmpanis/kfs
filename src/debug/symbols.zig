const multiboot = @import("arch").multiboot;
const std = @import("std");
const mm = @import("kernel").mm;


var symbol_table: [*]std.elf.Elf32_Sym = undefined;
var symbol_count: usize = 0;
var string_table: [*]u8 = undefined;
var offset_buffer: [256]u8 = undefined;

pub fn initSymbolTable(boot_info: *const multiboot.MultibootInfo) void {
    const MULTIBOOT_ELF_SECTIONS = (1 << 5);
    
    if ((boot_info.flags & MULTIBOOT_ELF_SECTIONS) == 0) {
        return;
    }
    const section_count = boot_info.syms_0;
    const section_shndx = boot_info.syms_3;
    const section_headers: [*]std.elf.Elf32_Shdr = @ptrFromInt(boot_info.syms_2 + mm.PAGE_OFFSET);

    var symtab_hdr: *std.elf.Elf32_Shdr = undefined;
    var strtab_hdr: *std.elf.Elf32_Shdr = undefined;
    for (0..section_count) |i| {
        const header = &section_headers[i];
        if (header.sh_type == std.elf.SHT_SYMTAB) {
            symtab_hdr = header;
        } else if (header.sh_type == std.elf.SHT_STRTAB and i != section_shndx) {
            strtab_hdr = header;
        }
    }
    symbol_table = @ptrFromInt(symtab_hdr.sh_addr + mm.PAGE_OFFSET);
    symbol_count = symtab_hdr.sh_size / symtab_hdr.sh_entsize;
    string_table = @ptrFromInt(strtab_hdr.sh_addr + mm.PAGE_OFFSET);
}

pub fn lookupSymbol(addr: usize) ?[]const u8 {
    
    var closest_symbol: ?*std.elf.Elf32_Sym = null;
    var closest_distance: usize = std.math.maxInt(usize);
    
    for (0..symbol_count) |i| {
        const sym = &symbol_table[i];
        
        if (sym.st_size == 0) {
            continue;
        }
        if (addr >= sym.st_value and addr < sym.st_value + sym.st_size) {
            const name: [*:0]const u8 = @ptrCast(@alignCast(&string_table[sym.st_name]));
            return std.mem.span(name);
        }
        
        const distance = if (addr > sym.st_value) 
            addr - sym.st_value 
        else 
            closest_distance;
        
        if (distance < closest_distance) {
            closest_symbol = sym;
            closest_distance = distance;
        }
    }

    if (closest_symbol != null and closest_distance < 4096) {
        const name: [*:0]const u8 = @ptrCast(@alignCast(&string_table[closest_symbol.?.st_name]));
        // Add offset indicator to show it's not an exact match
        const offset_str = std.fmt.bufPrint(&offset_buffer, "{s}+0x{x}", .{
            std.mem.span(name), 
            closest_distance
        }) catch offset_buffer[0..];
        return offset_str;
    }

    return null;
}
