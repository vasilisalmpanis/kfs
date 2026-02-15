const std = @import("std");
const arch = @import("arch");
const krn = @import("../main.zig");

// ELF constants
const EI_CLASS = 4;
const EI_DATA = 5;
const EI_VERSION = 6;

const ELFCLASS32 = 1;
const ELFCLASS64 = 2;

const ELFDATA2LSB = 1;

const EV_CURRENT = 1;

const PIE_LOAD_BASE: usize = 0x0001_0000; // base addr where to load PIE static binaries

const PT_TYPE = enum (u32) {
    PT_NULL = 0,
    PT_LOAD = 1,
    PT_DYNAMIC = 2,
    PT_INTERP = 3,
    _,
};

pub const HEAP_MMAP_GAP: usize = 4 * 1024 * 1024;

pub const argv_init: []const []const u8 = &[_][]const u8{
    "init",
};
pub const envp_init: []const []const u8 = &[_][]const u8{
    "HOME=/root",
    "TERM=xterm-256color",
    "TERMINFO=/usr/share/terminfo",
    "VIM=/usr/share/vim",
};

const AuxEntry = struct {
    key: usize,
    val: usize,
};

const auxv: [2]AuxEntry = .{
    AuxEntry{
        .key = 6,
        .val = krn.mm.PAGE_SIZE,
    },
    AuxEntry{
        .key = 0,
        .val = 0,
    }
};

pub const ElfValidationError = error {
    InvalidMagic,
    UnsupportedClass,
    UnsupportedEndianness,
    UnsupportedVersion,
    UnsupportedMachine,
    UnsupportedType,
    InvalidHeaderSize,
    FileTooSmall,
    DynamicLoaderRequired,
};

pub fn validateElfHeader(userspace: []const u8) !void{

    if (userspace.len < @sizeOf(std.elf.Elf32_Ehdr)) {
        return ElfValidationError.FileTooSmall;
    }

    if (!std.mem.eql(u8, userspace[0..4], &[4]u8{0x7F, 'E', 'L', 'F'})) {
        return ElfValidationError.InvalidMagic;
    }

    const ei_class = userspace[EI_CLASS];
    if (ei_class != ELFCLASS32)
        return ElfValidationError.UnsupportedClass;

    const ei_data = userspace[EI_DATA];
    if (ei_data != ELFDATA2LSB) {
        return ElfValidationError.UnsupportedEndianness;
    }
    const ei_version = userspace[EI_VERSION];
    if (ei_version != EV_CURRENT) {
        return ElfValidationError.UnsupportedVersion;
    }

    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));

    if (ehdr.e_machine != std.elf.EM.@"386") {
        return ElfValidationError.UnsupportedMachine;
    }

    if (ehdr.e_ehsize != @sizeOf(std.elf.Elf32_Ehdr)) {
        return ElfValidationError.InvalidHeaderSize;
    }

    if (ehdr.e_type != .EXEC and ehdr.e_type != .DYN) {
        return ElfValidationError.UnsupportedType;
    }

    if (!checkKernelLoadable32(userspace, ehdr))
        return ElfValidationError.DynamicLoaderRequired;
}

fn checkKernelLoadable32(userspace: []const u8, ehdr: *const std.elf.Elf32_Ehdr) bool {
    var has_interp = false;

    for (0..ehdr.e_phnum) |i| {
        if (ehdr.e_phoff + (ehdr.e_phentsize * i) + @sizeOf(std.elf.Elf32_Phdr) > userspace.len) {
            break;
        }

        const p_hdr: *const std.elf.Elf32_Phdr = @ptrCast(
            @alignCast(&userspace[ehdr.e_phoff + (ehdr.e_phentsize * i)])
        );

        const header_type: PT_TYPE = @enumFromInt(p_hdr.p_type);
        switch (header_type) {
            .PT_INTERP => has_interp = true,
            else => {},
        }
    }
    return !has_interp;
}

pub fn setEnvironment(stack_bottom: usize, stack_size: usize, argv: []const []const u8, envp: []const []const u8) void {
    // Auxiliary vector
    var argv_str_size: usize = 0;
    for (argv) |arg| {
        argv_str_size += arg.len + 1;
    }
    var envp_str_size: usize = 0;
    for (envp) |env| {
        envp_str_size += env.len + 1;
    }
    const argv_ptr_size = @sizeOf(usize) * (argv.len + 1);
    const envp_ptr_size = @sizeOf(usize) * (envp.len + 1);
    const auxv_size = @sizeOf(AuxEntry) * auxv.len;
    const argc_size = @sizeOf(usize);
    const end_marker_size = @sizeOf(usize);

    const size = argv_ptr_size + argv_str_size + envp_ptr_size +
                        envp_str_size + auxv_size + argc_size + end_marker_size;
    var aligned_size = size;
    if (aligned_size % 16 != 0)
        aligned_size += 16 - (aligned_size % 16);

    const stack_ptr_addr: usize = stack_bottom + stack_size - aligned_size;
    var strings: [*]u8 = @ptrFromInt(stack_bottom + stack_size - end_marker_size - argv_str_size - envp_str_size);
    var pointers: [*]usize = @ptrFromInt(stack_ptr_addr);
    var str_off: usize = 0;
    var ptr_off: usize = 0;

    // Set argc
    krn.task.current.mm.?.argc = stack_ptr_addr;
    pointers[ptr_off] = argv.len;
    ptr_off += 1;

    // Set argv
    krn.task.current.mm.?.arg_start = @intFromPtr(strings) + str_off;
    for (argv) |arg| {
        @memcpy(strings[str_off..str_off + arg.len], arg);
        strings[str_off + arg.len] = 0;
        pointers[ptr_off] = @intFromPtr(&strings[str_off]);
        str_off += arg.len + 1;
        ptr_off += 1;
    }
    krn.task.current.mm.?.arg_end = @intFromPtr(strings) + str_off;
    pointers[ptr_off] = 0;
    ptr_off += 1;

    // Set envp
    krn.task.current.mm.?.env_start = stack_ptr_addr + argv_ptr_size;
    krn.task.current.mm.?.env_end = krn.task.current.mm.?.env_start + envp_ptr_size;
    for (envp) |env| {
        @memcpy(strings[str_off..str_off + env.len], env);
        strings[str_off + env.len] = 0;
        pointers[ptr_off] = @intFromPtr(&strings[str_off]);
        str_off += env.len + 1;
        ptr_off += 1;
    }
    pointers[ptr_off] = 0;
    ptr_off += 1;
    // end marker after strings
    @memset(strings[str_off..str_off + 4], 0);

    // Set auxv
    var aux_ptr: [*]AuxEntry = @ptrCast(&pointers[ptr_off]);
    ptr_off = 0;
    for (auxv) |aux| {
        aux_ptr[ptr_off] = aux;
        ptr_off += 1;
    }
}

pub fn prepareBinary(userspace: []const u8, argv: []const []const u8, envp: []const []const u8) !void {

    const stack_pages: u32 = 30;
    var heap_start: usize = 0;

    const prot: u32 = krn.mm.PROT_RW;
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));
    const is_pie = ehdr.e_type == .DYN;
    const load_base: usize = if (is_pie) PIE_LOAD_BASE else 0;

    for (0..ehdr.e_phnum) |i| {
        const p_hdr: *std.elf.Elf32_Phdr = @ptrCast(
            @constCast(@alignCast(&userspace[ehdr.e_phoff + (ehdr.e_phentsize * i)]))
        );
        const header_type: PT_TYPE = @enumFromInt(p_hdr.p_type);
        if (header_type != PT_TYPE.PT_LOAD) {
            continue;
        }
        var num_pages = p_hdr.p_memsz / arch.PAGE_SIZE;
        if (!arch.isPageAligned(p_hdr.p_memsz))
            num_pages += 1;

        // Create anonymous mapping for each section with proper page alignment
        const seg_start = load_base + p_hdr.p_vaddr;
        const seg_end = seg_start + p_hdr.p_memsz;
        const page_start = arch.pageAlign(seg_start, true);  // Round down to page boundary
        const page_end = arch.pageAlign(seg_end, false);  // Round up to page boundary
        const aligned_size = page_end - page_start;

        _ = krn.task.current.mm.?.mmap_area(
            page_start,
            aligned_size,
            prot,
            krn.mm.MAP.anonymous(),
            null,
            0
        ) catch {return ;};
        const section_ptr: [*]u8 = @ptrFromInt(seg_start);
        if (p_hdr.p_filesz > 0) {
            @memcpy(
                section_ptr[0..p_hdr.p_filesz],
                userspace[p_hdr.p_offset..p_hdr.p_offset + p_hdr.p_filesz]
            );
        }
        if (p_hdr.p_memsz > p_hdr.p_filesz) {
            @memset(section_ptr[p_hdr.p_filesz..p_hdr.p_memsz], 0);
        }
        if (seg_end > heap_start)
            heap_start = seg_end;
    }
    const stack_size: usize = stack_pages * arch.PAGE_SIZE;
    var stack_bottom: usize = krn.mm.PAGE_OFFSET - stack_pages * arch.PAGE_SIZE;
    stack_bottom = krn.task.current.mm.?.mmap_area(
        stack_bottom,
        stack_size,
        prot,
        krn.mm.MAP.anonymous(),
        null,
        0
    ) catch {
        @panic("Unable to go to userspace\n");
    };
    const stack_ptr: [*]u8 = @ptrFromInt(stack_bottom);
    @memset(stack_ptr[0..stack_size], 0);

    setEnvironment(stack_bottom, stack_size, argv, envp);

    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{stack_bottom, stack_bottom + stack_size});
    const entry = load_base + ehdr.e_entry;
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{entry});

    // Also arch specific
    heap_start = arch.pageAlign(heap_start, false);
    krn.logger.INFO("heap_start 0x{X:0>8}\n", .{heap_start});
    krn.task.current.mm.?.brk_start = heap_start;
    krn.task.current.mm.?.brk = heap_start;
    krn.task.current.mm.?.heap = heap_start + HEAP_MMAP_GAP;
    krn.task.current.mm.?.stack_bottom = stack_bottom;
    krn.task.current.mm.?.stack_top = stack_bottom + stack_size;
    krn.task.current.mm.?.code = entry;
    krn.task.current.tsktype = .PROCESS;
}

pub fn goUserspace() void {
    arch.idt.goUserspace();
}
