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

const PT_TYPE = enum (u32) {
    PT_NULL = 0,
    PT_LOAD = 1,
    PT_DYNAMIC = 2,
    PT_INTERP = 3,
    _,
};

pub const argv_init: []const []const u8 = &[_][]const u8{
    "init",
};
pub const envp_init: []const []const u8 = &[_][]const u8{
    "HOME=/",
    "TERM=kfs",
};

const AuxEntry = struct {
    key: u32,
    val: u32,
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
    InvalidHeaderSize,
    FileTooSmall,
    Dynamic,
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

    const is_statically_linked = checkStaticLinking32(userspace, ehdr);
    if (!is_statically_linked)
        return ElfValidationError.Dynamic;
}

fn checkStaticLinking32(userspace: []const u8, ehdr: *const std.elf.Elf32_Ehdr) bool {
    var has_interp = false;
    var has_dynamic = false;

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
            .PT_DYNAMIC => has_dynamic = true,
            else => {},
        }
    }
    return !has_interp and !has_dynamic;
}

pub fn setEnvironment(stack_bottom: u32, stack_size: u32, argv: []const []const u8, envp: []const []const u8) void {
    // Auxiliary vector
    var argv_str_size: u32 = 0;
    for (argv) |arg| {
        argv_str_size += arg.len + 1;
    }
    var envp_str_size: u32 = 0;
    for (envp) |env| {
        envp_str_size += env.len + 1;
    }
    const argv_ptr_size = @sizeOf(u32) * (argv.len + 1);
    const envp_ptr_size = @sizeOf(u32) * (envp.len + 1);
    const auxv_size = @sizeOf(AuxEntry) * auxv.len;
    const argc_size = @sizeOf(u32);
    const end_marker_size = @sizeOf(u32);

    const size = argv_ptr_size + argv_str_size + envp_ptr_size +
                        envp_str_size + auxv_size + argc_size + end_marker_size;
    var aligned_size = size;
    if (aligned_size % 16 != 0)
        aligned_size += 16 - (aligned_size % 16);
    
    const stack_ptr_addr: u32 = stack_bottom + stack_size - aligned_size;
    var strings: [*]u8 = @ptrFromInt(stack_bottom + stack_size - end_marker_size - argv_str_size - envp_str_size);
    var pointers: [*]u32 = @ptrFromInt(stack_ptr_addr);
    var str_off: u32 = 0;
    var ptr_off: u32 = 0;
    
    // Set argc
    pointers[ptr_off] = argv.len;
    ptr_off += 1;

    // Set argv
    krn.task.current.mm.?.arg_start = stack_ptr_addr;
    krn.task.current.mm.?.arg_end = stack_ptr_addr + argv_ptr_size;
    for (argv) |arg| {
        @memcpy(strings[str_off..str_off + arg.len], arg);
        strings[str_off + arg.len] = 0;
        pointers[ptr_off] = @intFromPtr(&strings[str_off]);
        str_off += arg.len + 1;
        ptr_off += 1;
    }
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
    krn.task.current.mm.?.arg_start = stack_ptr_addr;
}

pub fn prepareBinary(userspace: []const u8, argv: []const []const u8, envp: []const []const u8) !void {
    validateElfHeader(userspace) catch |err| {
        krn.logger.ERROR("ELF validation failed: {}\n", .{err});
        while (true) {}
        return;
    };

    krn.logger.INFO("Binary validation: 32-bit and statically_linked\n", .{});

    const stack_pages: u32 = 10;
    var heap_start: u32 = 0;

    const prot: u32 = krn.mm.PROC_RW;
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(userspace));

    krn.logger.INFO("Goind to userspace {any}\n", .{ehdr});
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
        const page_start = arch.pageAlign(p_hdr.p_vaddr, true);  // Round down to page boundary
        const page_end = arch.pageAlign(p_hdr.p_vaddr + p_hdr.p_memsz, false);  // Round up to page boundary
        const aligned_size = page_end - page_start;

        _ = krn.task.current.mm.?.mmap_area(
            page_start,
            aligned_size,
            prot,
            krn.mm.MAP.anonymous()
        ) catch {return ;};
        const section_ptr: [*]u8 = @ptrFromInt(p_hdr.p_vaddr);
        if (p_hdr.p_filesz > 0) {
            @memcpy(
                section_ptr[0..p_hdr.p_filesz],
                userspace[p_hdr.p_offset..p_hdr.p_offset + p_hdr.p_filesz]
            );
        }
        if (p_hdr.p_memsz > p_hdr.p_filesz) {
            @memset(section_ptr[p_hdr.p_filesz..p_hdr.p_memsz], 0);
        }
        if (p_hdr.p_vaddr + p_hdr.p_memsz > heap_start)
            heap_start = p_hdr.p_vaddr + p_hdr.p_memsz;
    }
    const stack_size: u32 = stack_pages * arch.PAGE_SIZE;
    var stack_bottom: u32 = krn.mm.PAGE_OFFSET - stack_pages * arch.PAGE_SIZE;
    stack_bottom = krn.task.current.mm.?.mmap_area(
        stack_bottom,
        stack_size,
        prot,
        krn.mm.MAP.anonymous()
    ) catch {
        @panic("Unable to go to userspace\n");
    };
    const stack_ptr: [*]u8 = @ptrFromInt(stack_bottom);
    @memset(stack_ptr[0..stack_size], 0);

    setEnvironment(stack_bottom, stack_size, argv, envp);

    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{stack_bottom, stack_bottom + stack_size});
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{ehdr.e_entry});

    arch.gdt.tss.esp0 = krn.task.current.regs.esp;
    heap_start = arch.pageAlign(heap_start, false);
    krn.logger.INFO("heap_start 0x{X:0>8}\n", .{heap_start});
    krn.task.current.mm.?.heap = heap_start;
    krn.task.current.mm.?.stack_bottom = stack_bottom;
    krn.task.current.mm.?.stack_top = stack_bottom + stack_size;
    krn.task.current.mm.?.code = ehdr.e_entry;
    krn.task.current.tsktype = .PROCESS;
}

pub fn goUserspace() void {

    asm volatile(
        \\ cli
        \\ mov $((8 * 4) | 3), %%bx
        \\ mov %%bx, %%ds
        \\ mov %%bx, %%es
        \\ mov %%bx, %%fs
        \\ mov %%bx, %%gs
        \\
        \\ push $((8 * 4) | 3)
        \\ push %[us]
        \\ pushf
        \\ pop %%ebx
        \\ or $0x200, %%ebx
        \\ push %%ebx
        \\ push $((8 * 3) | 3)
        \\ push %[uc]
        \\ iret
        \\
        ::
        [uc] "r" (krn.task.current.mm.?.code),
        [us] "r" (krn.task.current.mm.?.arg_start),
    );
}
