const kernel = @import("kernel");
const arch = @import("arch");
const debug = @import("debug");
const std = @import("std");

pub var modules_list: ?*Module = null;
pub var modules_mutex = kernel.Mutex.init();

pub const Module = struct {
    name: []const u8,
    exit: ?*const fn() callconv(.c) void,
    list: kernel.list.ListHead,
    code: []u8 = undefined,
    // deps
    // version
    // Lock
};

const PT_TYPE = enum (u32) {
    PT_NULL = 0,
    PT_LOAD = 1,
    PT_DYNAMIC = 2,
    PT_INTERP = 3,
    _,
};

pub const R_X86_Type = enum(u8) {
    R_386_NONE = 0,
    R_386_32 = 1,
    R_386_PC32 = 2,
    R_386_GOT32 = 3,
    R_386_PLT32 = 4,
    R_386_COPY = 5,
    R_386_GLOB_DAT = 6,
    R_386_JMP_SLOT = 7,
    R_386_RELATIVE = 8,
    R_386_GOTOFF = 9,
    R_386_GOTPC = 10,
    R_386_32PLT = 11,
    R_386_16 = 20,
    R_386_PC16 = 21,
    R_386_8 = 22,
    R_386_PC8 = 23,
    R_386_SIZE32 = 28,
    _
};

fn unpackU32(bytes: [*]u8) u32 {
    return (
        @as(u32, @intCast(bytes[0])) << 0
           | @as(u32, @intCast(bytes[1])) << 8
           | @as(u32, @intCast(bytes[2])) << 16
           | @as(u32, @intCast(bytes[3])) << 24
    );
}

fn packU32(bytes: [*]u8, val: u32) void {
    bytes[0] = @truncate(val >> 0);
    bytes[1] = @truncate(val >> 8);
    bytes[2] = @truncate(val >> 16);
    bytes[3] = @truncate(val >> 24);
}

pub fn do_relocations(
    sh: *std.elf.Elf32_Shdr,
    elf: []u8,
    sh_arr: [*]std.elf.Elf32_Shdr,
    sh_strtab: *std.elf.Elf32_Shdr,
) !void {
    const sh_symtab = sh_arr[sh.sh_link];
    const sh_target = sh_arr[sh.sh_info];
    const symtab: [*]std.elf.Elf32_Sym = @ptrCast(@alignCast(
        &elf[sh_symtab.sh_offset]
    ));
    const strtab: [*]u8 = @ptrCast(@alignCast(
        &elf[sh_strtab.sh_offset]
    ));
    const rel_entries: [*]std.elf.Elf32_Rel = @ptrCast(@alignCast(
        &elf[sh.sh_offset]
    ));
    const rel_count = sh.sh_size / sh.sh_entsize;
    for (0..rel_count) |idx| {
        const rel = rel_entries[idx];
        const sym = symtab[rel.r_sym()];
        const write_addr: [*]u8 = @ptrFromInt(
            sh_target.sh_addr + rel.r_offset
        );
        const sym_sh = sh_arr[sym.st_shndx];
        const P: u32 = @intFromPtr(write_addr);
        const A: u32 = unpackU32(write_addr);
        var S: u32 = sym_sh.sh_addr + sym.st_value;
        
        if (sym.st_shndx == std.elf.SHN_ABS) {
            S = sym.st_value;
        } else if (sym.st_shndx == std.elf.SHN_UNDEF) {
            // We have no dynamic linking
            // we find the symbol value and use it as S
            // in the formula
            const name: [:0]const u8 = std.mem.span(@as([*:0]u8, @ptrCast(@alignCast(&strtab[sym.st_name]))));
            const symbol = debug.lookupSymbolByName(name) catch {
                kernel.logger.ERROR("Symbol Not Found: {s}\n", .{name});
                return kernel.errors.PosixError.ENOENT;
            };
            S = symbol.st_value;
        }
        const rel_type: R_X86_Type = @enumFromInt(rel.r_type());
        // kernel.logger.DEBUG("{t} [{s}]: A: {x} S: {x} P: {x}\n", .{
        //     rel_type,
        //     std.mem.span(@as([*:0]u8, @ptrCast(@alignCast(&strtab[sym.st_name])))),
        //     A, S, P
        // });
        switch (rel_type) {
            .R_386_32 => {
                packU32(write_addr, S + A);
            },
            .R_386_PLT32,
            .R_386_PC32 => {
                const P64: i64 = @intCast(P);
                const A64: i64 = @intCast(A);
                const S64: i64 = @intCast(S);
                const diff: i32 = @truncate(A64 + S64 - P64);
                packU32(
                    write_addr,
                    @bitCast(diff)
                );
            },
            else => {
                kernel.logger.ERROR(
                    "Relocation {t} not implemented!",
                    .{rel_type}
                );
            }
        }
    }
}

fn alignSize(size: u32, alignment: u32) u32 {
    if (size % alignment != 0) {
        return size + (alignment - size % alignment);
    }
    return size;
}

fn get_module_total_size(elf_headers: [*]std.elf.Elf32_Shdr, count: u32) u32 {
    var offset: u32 = 0;
    var max_alignment: u32 = 0;
    for (0..count) |idx| {
        const header: std.elf.Elf32_Shdr = elf_headers[idx];
        if (header.sh_size == 0)
            continue;
        offset = alignSize(offset, header.sh_addralign);
        offset += header.sh_size;
        if (header.sh_addralign > max_alignment)
            max_alignment = header.sh_addralign;
    }
    return offset + max_alignment;
}

fn place_sections(module: []u8, binary: []u8, section_hdrs: []std.elf.Elf32_Shdr) !void {
    var offset: u32 = 0;
    const load_address: u32 = @intFromPtr(module.ptr);
    for (section_hdrs, 0..) |header, idx| {
        // Maybe incorrect
        if (header.sh_size == 0)
            continue;
        if (offset == 0) {
            if (load_address % header.sh_addralign != 0) {
                offset += header.sh_addralign - load_address % header.sh_addralign;
            }
        }
        const temp: *std.elf.Elf32_Shdr = &section_hdrs[idx];
        if (load_address + offset % header.sh_addralign != 0) {
            const aligned: u32 = alignSize(load_address + offset, header.sh_addralign);
            offset += aligned - (load_address + offset);
        }
        temp.sh_addr = load_address + offset;
        if (header.sh_type == std.elf.SHT_NOBITS) {
            offset += header.sh_size;
            continue;
        }
        @memcpy(module[offset..offset + header.sh_size], binary[header.sh_offset..header.sh_offset + header.sh_size]);
        offset += header.sh_size;
    }
}

pub fn load_module(slice: []u8, name: []const u8) !*Module {
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(slice.ptr));
    const sh_hdr: *std.elf.Elf32_Shdr = @ptrCast(
        @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * ehdr.e_shstrndx)]))
    );
    const sh_arr: [*]std.elf.Elf32_Shdr = @ptrCast(@alignCast(
        &slice[ehdr.e_shoff]
    ));

    // Find size, allocate and set to 0 and place sections
    const total_size = get_module_total_size(sh_arr, ehdr.e_shnum);
    const module = if (kernel.mm.kmallocSlice(u8, total_size)) |_module|
        _module
    else
        return kernel.errors.PosixError.ENOMEM;
    @memset(module[0..], 0);
    kernel.logger.DEBUG(
        "MOD {s} loaded at: 0x{x} - 0x{x}\n",
        .{
            name,
            @intFromPtr(module.ptr),
            @intFromPtr(module.ptr) + module.len
        }
    );
    try place_sections(module, slice, sh_arr[0..ehdr.e_shnum]);
    
    const section_strings: [*]u8 = @ptrCast(&slice[sh_hdr.sh_offset]);
    var sh_symtab: *std.elf.Elf32_Shdr = undefined;
    var sh_strtab: *std.elf.Elf32_Shdr = undefined;
    var init: ?*const fn() callconv(.c) u32 = null;
    var exit: ?*const fn() callconv(.c) void = null;
    for (0..ehdr.e_shnum) |i| {
        const section_hdr: *std.elf.Elf32_Shdr = @ptrCast(
            @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * i)]))
        );
        if (section_hdr.sh_type == std.elf.SHT_SYMTAB) {
            sh_symtab = section_hdr;
        } else if (section_hdr.sh_type == std.elf.SHT_STRTAB and i != ehdr.e_shstrndx) {
            sh_strtab = section_hdr;
        }
        const section_name: [*:0]u8 = @ptrCast(&section_strings[section_hdr.sh_name]);
        const span: [:0]const u8 = std.mem.span(section_name);
        if (std.mem.eql(u8, span, ".init")) {
            init = @ptrFromInt(section_hdr.sh_addr);

        } else if (std.mem.eql(u8, span, ".exit")) {
            exit = @ptrFromInt(section_hdr.sh_addr);
        }
    }
    for (0..ehdr.e_shnum) |i| {
        const section_hdr: *std.elf.Elf32_Shdr = @ptrCast(
            @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * i)]))
        );
        if (section_hdr.sh_type == std.elf.SHT_REL) {
            try do_relocations(section_hdr, slice, sh_arr, sh_strtab);
        }
    }
    const ret: u32 = init.?();
    if (ret != 0) {
        return kernel.errors.PosixError.EINVAL;
    }

    if (kernel.mm.kmalloc(Module)) |mod| {
        errdefer kernel.mm.kfree(mod);
        mod.exit = exit;       
        mod.list.setup();
        const name_len = if (std.mem.lastIndexOf(u8, name, ".")) |idx|
            idx
        else
            name.len;
        if (kernel.mm.kmallocSlice(u8, name_len)) |_name| {
            @memcpy(_name[0..name_len], name[0..name_len]);
            mod.name = _name;
        } else {
            return kernel.errors.PosixError.ENOMEM;
        }
        mod.code = module;
        addModule(mod);
        return mod;
    }
    if (exit != null) {
        exit.?();
    }
    return kernel.errors.PosixError.ENOMEM;
}

fn addModule(mod: *Module) void {
    modules_mutex.lock();
    defer modules_mutex.unlock();
    if (modules_list) |head| {
        head.list.addTail(&mod.list);
    } else {
        modules_list = mod;
    }
}

pub fn removeModule(name: []const u8) !void {
    modules_mutex.lock();
    defer modules_mutex.unlock();

    if (modules_list) |head| {
        var it = head.list.iterator();
        while (it.next()) |i| {
            const _mod = i.curr.entry(Module, "list");
            if (std.mem.eql(u8, name, _mod.name)) {
                if (_mod.exit) |_exit| {
                    _exit();
                }
                if (_mod == modules_list) {
                    if (_mod.list.isEmpty()) {
                        modules_list = null;
                    } else {
                        modules_list = _mod.list.next.?.entry(Module, "list");
                    }
                }
                _mod.list.del();
                kernel.mm.kfree(_mod.name.ptr);
                kernel.mm.kfree(_mod.code.ptr);
                kernel.mm.kfree(_mod);
                kernel.logger.DEBUG("module removed: {s}", .{name});
                return ;
            }
        }
    }
    kernel.logger.DEBUG("No module found with name {s}", .{name});
    return kernel.errors.PosixError.ENOENT;
}
