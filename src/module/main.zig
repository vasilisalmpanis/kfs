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
