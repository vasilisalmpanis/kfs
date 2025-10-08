const kernel = @import("kernel");
const arch = @import("arch");
const debug = @import("debug");
const std = @import("std");

var modules_list: ?*Module = null;
var modules_mutex = kernel.Mutex.init();

pub const Module = struct {
    name: []const u8,
    exit: ?*const fn() callconv(.c) void,
    list: kernel.list.ListHead
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
    kernel.logger.INFO(
        "Target: {any}",
        .{sh_target}
    );
    const rel_count = sh.sh_size / sh.sh_entsize;
    for (0..rel_count) |idx| {
        const rel = rel_entries[idx];
        const sym = symtab[rel.r_sym()];
        const write_addr: [*]u8 = @ptrCast(@alignCast(
            &elf[sh_target.sh_offset + rel.r_offset]
        ));
        const sym_sh = sh_arr[sym.st_shndx];
        const load_base = @intFromPtr(elf.ptr); 
        // const GOT: u32 = load_base;
        const P: u32 = @intFromPtr(write_addr);
        const A: u32 = unpackU32(write_addr);
        var S: u32 = load_base + sym_sh.sh_offset + sym.st_value;
        const stype = sym.st_type();
        if (stype == std.elf.SHN_ABS) {
            S = sym.st_value;
        } else if (stype == std.elf.SHN_UNDEF) {
            // We have no dynamic linking
            // we find the symbol value and use it as S
            // in the formula
            const name: []const u8 = std.mem.span(@as([*:0]u8, @ptrCast(@alignCast(&strtab[sym.st_name]))));
            const symbol = debug.lookupSymbolByName(name) catch {
                kernel.logger.ERROR("Symbol Not Found: {s}\n", .{name});
                return kernel.errors.PosixError.ENOENT;
            };
            S = symbol.st_value;
        }
        const rel_type: R_X86_Type = @enumFromInt(rel.r_type());
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

pub fn load_module(path: kernel.fs.path.Path) !*Module {
    const inode = path.dentry.inode;
    if (!inode.mode.canExecute(inode.uid, inode.gid) or !inode.mode.isReg()) {
        return kernel.errors.PosixError.EACCES;
    }
    const file = try kernel.fs.File.new(path);
    errdefer file.ref.unref();
    const slice = if (kernel.mm.kmallocSlice(u8, file.inode.size)) |_slice|
        _slice 
    else
        return kernel.errors.PosixError.ENOMEM;
    var read: u32 = 0;
    while (read < file.inode.size) {
        read += try file.ops.read(file, @ptrCast(&slice[read]), slice.len);
    }
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(slice.ptr));
    const sh_hdr: *std.elf.Elf32_Shdr = @ptrCast(
        @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * ehdr.e_shstrndx)]))
    );
    const section_strings: [*]u8 = @ptrCast(&slice[sh_hdr.sh_offset]);
    const sh_arr: [*]std.elf.Elf32_Shdr = @ptrCast(@alignCast(
        &slice[ehdr.e_shoff]
    ));
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
        const name: [*:0]u8 = @ptrCast(&section_strings[section_hdr.sh_name]);
        const span = std.mem.span(name);
        if (std.mem.eql(u8, span, ".init")) {
            init = @ptrCast(&slice[section_hdr.sh_offset]);
        } else if (std.mem.eql(u8, span, ".exit")) {
            exit = @ptrCast(&slice[section_hdr.sh_offset]);
        }
    }
    if (init == null) {
        // Error
        kernel.logger.INFO("Module doesn't have init", .{});
        return kernel.errors.PosixError.EINVAL;
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
        if (kernel.mm.kmallocSlice(u8, path.dentry.name.len)) |name| {
            const mod_name: []u8 = path.dentry.name;
            @memcpy(name[0..mod_name.len], mod_name);
            mod.name = name;
        } else {
            return kernel.errors.PosixError.ENOMEM;
        }

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
