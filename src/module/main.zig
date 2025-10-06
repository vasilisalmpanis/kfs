const kernel = @import("kernel");
const std = @import("std");
const arch = @import("arch");

pub const ModuleCallbacks = extern struct {
    init: *const fn() callconv(.c) u32,
    exit: *const fn() callconv(.c) void,
};

pub const Module = struct {
    name: []const u8,
    // Lock
    // Entry in the global list of modules
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
) void {
    const sh_symtab = sh_arr[sh.sh_link];
    const sh_target = sh_arr[sh.sh_info];
    const symtab: [*]std.elf.Elf32_Sym = @ptrCast(@alignCast(
        &elf[sh_symtab.sh_offset]
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
        kernel.logger.INFO("rel: {any} {d} {x}", .{rel, rel.r_type(), rel.r_sym()});
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
        if (sym.st_type() == std.elf.SHN_ABS) {
            S = sym.st_value;
        }
        kernel.logger.INFO(
            \\
            \\     P: {x}
            \\     A: {x}
            \\     S: {x}
            \\
            , .{P, A, S}
        );
        const rel_type: R_X86_Type = @enumFromInt(rel.r_type());
        switch (rel_type) {
            .R_386_32 => {
                packU32(write_addr, S + A);
            },
            .R_386_PC32 => {
                var diff: u32 = 0;
                var sign: i32 = 1;
                if (P > A + S) {
                    diff = P - (A + S);
                    sign = -1;
                } else {
                    diff = (A + S) - P;
                }
                packU32(
                    write_addr,
                    @bitCast(@as(i32, @intCast(diff)) * sign)
                );
            },
            // .R_386_GOTPC => {
            //     write_addr.* = GOT + A - P;
            // },
            // .R_386_GOTOFF => {
            //     write_addr.* = S + A - GOT;
            // },
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
    kernel.logger.INFO("Executing {s} {d}\n", .{path.dentry.name, file.inode.size});
    // We are here
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(slice.ptr));
    kernel.logger.INFO("Header {any}\n", .{ehdr});
    const sh_hdr: *std.elf.Elf32_Shdr = @ptrCast(
        @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * ehdr.e_shstrndx)]))
    );
    kernel.logger.INFO("Before ptr cast\n", .{});
    const section_strings: [*]u8 = @ptrCast(&slice[sh_hdr.sh_offset]);
    kernel.logger.INFO("Before loop\n", .{});
    const sh_arr: [*]std.elf.Elf32_Shdr = @ptrCast(@alignCast(
        &slice[ehdr.e_shoff]
    ));
    var sh_symtab: *std.elf.Elf32_Shdr = undefined;
    var sh_strtab: *std.elf.Elf32_Shdr = undefined;
    for (0..ehdr.e_shnum) |i| {
        const section_hdr: *std.elf.Elf32_Shdr = @ptrCast(
            @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * i)]))
        );
        if (section_hdr.sh_type == std.elf.SHT_SYMTAB) {
            sh_symtab = section_hdr;
        } else if (section_hdr.sh_type == std.elf.SHT_STRTAB and i != ehdr.e_shstrndx) {
            sh_strtab = section_hdr;
        }
        if (section_hdr.sh_type == std.elf.SHT_REL) {
            do_relocations(section_hdr, slice, sh_arr);
        }
    }
    for (0..ehdr.e_shnum) |i| {
        const section_hdr: *std.elf.Elf32_Shdr = @ptrCast(
            @constCast(@alignCast(&slice[ehdr.e_shoff + (ehdr.e_shentsize * i)]))
        );
        kernel.logger.INFO("Index {d}\n", .{i});
        const name: [*:0]u8 = @ptrCast(&section_strings[section_hdr.sh_name]);
        const span = std.mem.span(name);
        if (std.mem.eql(u8, span, ".init")) {
            const function: *const fn() u32 = @ptrCast(&slice[section_hdr.sh_offset]);
            const result = function();
            kernel.logger.INFO("Result of init {d}\n", .{result});
        }
        // if (section_hdr.sh_size == 0)
        //     continue;
        // kernel.logger.INFO("section hdr {any}\n", .{section_hdr});
        // const from: u32 = section_hdr.sh_offset;
        // const to: u32 = section_hdr.sh_offset + section_hdr.sh_size;
        // @memcpy(module_memory[from..to], slice[from..to]);
        // if (section_hdr.sh_type == std.elf.SHT_SYMTAB) {
        //     // symtab_hdr = header;
        // } else if (section_hdr.sh_type == std.elf.SHT_STRTAB and i != ehdr.e_shstrndx) {
        //     // strtab_hdr = header;
        // }
    }
    if (kernel.mm.kmalloc(Module)) |mod| {
        return mod;
    }
    return kernel.errors.PosixError.ENOMEM;
}
