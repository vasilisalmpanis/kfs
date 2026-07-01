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
const INTERP_LOAD_BASE: usize = 0x8000_0000;

const PT_TYPE = enum (u32) {
    PT_NULL = 0,
    PT_LOAD = 1,
    PT_DYNAMIC = 2,
    PT_INTERP = 3,
    _,
};

// Elf Program Segment flags
const PF_X: u32 = 0x1;
const PF_W: u32 = 0x2;
const PF_R: u32 = 0x4;

fn PFtoProt(flags: u32) u32 {
    var res: u32 = 0;
    if (flags & PF_R != 0)
        res |= krn.mm.PROT_READ;
    if (flags & PF_W != 0)
        res |= krn.mm.PROT_WRITE;
    return res;
}

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

const AT_NULL = 0;
const AT_PHDR = 3;  // address of program headers in memory
const AT_PHENT = 4; // size of one program header
const AT_PHNUM = 5; // number of program headers
const AT_PAGESZ = 6;
const AT_BASE = 7;  // load base for PIE
const AT_ENTRY = 9; // entry point address
const AT_SYSINFO_EHDR = 33; // vDSO ELF header address

const vdso = @import("../vdso.zig");

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
}

pub fn setEnvironment(
    stack_bottom: usize,
    stack_size: usize,
    argv: []const []const u8,
    envp: []const []const u8,
    aux_entries: []const AuxEntry,
) void {
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
    const auxv_size = @sizeOf(AuxEntry) * aux_entries.len;
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
    for (aux_entries) |aux| {
        aux_ptr[ptr_off] = aux;
        ptr_off += 1;
    }
}

/// Returns end address of last mapped segment
fn loadSegments(elf: []const u8, load_base: usize) !struct{
    load_addr: usize,
    end_addr: usize
} {
    var load_addr: usize = 0;
    var end_addr: usize = 0;
    var load_addr_set: bool = false;
    const prot: u32 = krn.mm.PROT_RW;
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(elf));
    for (0..ehdr.e_phnum) |i| {
        const p_hdr: *std.elf.Elf32_Phdr = @ptrCast(
            @constCast(@alignCast(&elf[ehdr.e_phoff + (ehdr.e_phentsize * i)]))
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
            prot, // TODO: remap later with PFtoProt(p_hdr.p_flags),
            krn.mm.MAP.anonymous(),
            null,
            0
        ) catch {
            krn.task.current.mm.?.releaseMappings();
            return krn.errors.PosixError.ENOMEM;
        };
        const section_ptr: [*]u8 = @ptrFromInt(seg_start);
        if (p_hdr.p_filesz > 0) {
            @memcpy(
                section_ptr[0..p_hdr.p_filesz],
                elf[p_hdr.p_offset..p_hdr.p_offset + p_hdr.p_filesz]
            );
        }
        if (p_hdr.p_memsz > p_hdr.p_filesz) {
            @memset(section_ptr[p_hdr.p_filesz..p_hdr.p_memsz], 0);
        }
        if (!load_addr_set) {
            load_addr_set = true;
            load_addr = p_hdr.p_vaddr - p_hdr.p_offset;
        }
        if (seg_end > end_addr)
            end_addr = seg_end;
    }
    return .{
        .load_addr = load_addr,
        .end_addr = end_addr,
    };
}

pub fn prepareBinary(
    elf_binary: []const u8,
    argv: []const []const u8,
    envp: []const []const u8
) !void {

    const stack_pages: u32 = 30;
    var heap_start: usize = 0;
    var final_eip: u32 = 0;
    var interp_binary: ?[] u8 = null;
    var interp_entry: usize = 0;

    const prot: u32 = krn.mm.PROT_RW;
    const ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(elf_binary));
    const is_pie = ehdr.e_type == .DYN;
    const load_base: usize = if (is_pie) PIE_LOAD_BASE else 0;

    for (0..ehdr.e_phnum) |i| {
        const p_hdr: *std.elf.Elf32_Phdr = @ptrCast(
            @constCast(@alignCast(&elf_binary[ehdr.e_phoff + (ehdr.e_phentsize * i)]))
        );
        const header_type: PT_TYPE = @enumFromInt(p_hdr.p_type);
        if (header_type == PT_TYPE.PT_INTERP) {
            // Check that there is no other interp
            if (interp_binary != null)
                return krn.errors.PosixError.ENOEXEC;

            const interp_name: []const u8 = std.mem.span(
                @as([*:0]const u8, @ptrCast(elf_binary.ptr + p_hdr.p_offset))
            );
            const path = try krn.fs.path.resolve(interp_name);

            defer path.release();
            const file = try krn.fs.File.new(path);
            defer file.ref.put();
            if (!file.inode.mode.canExecute(krn.task.current.uid, krn.task.current.gid))
                return krn.errors.PosixError.EPERM;
            interp_binary = krn.mm.kmallocSlice(u8, file.inode.size) orelse
                return krn.errors.PosixError.ENOMEM;
            var bytes_read: u32 = 0;
            while (bytes_read < file.inode.size) {
                const res: u32 = try file.ops.read(
                    file,
                    interp_binary.?.ptr + bytes_read,
                    interp_binary.?.len - bytes_read
                );
                bytes_read += res;
            }
            try validateElfHeader(interp_binary.?);
        }
    }
    defer if (interp_binary != null) krn.mm.kfreeSlice(interp_binary.?);

    const elf_addrs = try loadSegments(elf_binary, load_base);
    heap_start = elf_addrs.end_addr;
    if (interp_binary) |_int_bin| {
        const int_ehdr: *const std.elf.Elf32_Ehdr = @ptrCast(@alignCast(interp_binary));
        interp_entry = int_ehdr.e_entry;
        _ = try loadSegments(_int_bin, INTERP_LOAD_BASE);
    }

    const stack_size: usize = stack_pages * arch.PAGE_SIZE;
    const vdso_code_pages = vdso.imagePages();
    const vdso_total_pages = 1 + vdso_code_pages; // vvar + code
    var stack_bottom: usize = krn.mm.PAGE_OFFSET - stack_pages * arch.PAGE_SIZE - vdso_total_pages * arch.PAGE_SIZE;
    stack_bottom = krn.task.current.mm.?.mmap_area(
        stack_bottom,
        stack_size,
        prot,
        krn.mm.MAP.anonymous(),
        null,
        0
    ) catch {
        krn.task.current.mm.?.releaseMappings();
        return krn.errors.PosixError.ENOMEM;
    };
    const stack_ptr: [*]u8 = @ptrFromInt(stack_bottom);
    @memset(stack_ptr[0..stack_size], 0);

    // Map vDSO and vvar pages above the stack
    const vdso_base = stack_bottom + stack_size; // vvar page
    const vdso_ehdr_addr = vdso_base + arch.PAGE_SIZE; // vDSO ELF code
    vdso.mapIntoUserspace(krn.task.current.mm.?, vdso_base) catch {
        krn.task.current.mm.?.releaseMappings();
        return krn.errors.PosixError.ENOMEM;
    };

    var aux_buf: [10]AuxEntry = undefined;
    var aux_count: usize = 0;
    if (is_pie or interp_binary != null) {
        aux_buf[aux_count] = .{ .key = AT_PHDR, .val = load_base + elf_addrs.load_addr + ehdr.e_phoff };
        aux_count += 1;
        aux_buf[aux_count] = .{ .key = AT_PHENT, .val = ehdr.e_phentsize };
        aux_count += 1;
        aux_buf[aux_count] = .{ .key = AT_PHNUM, .val = ehdr.e_phnum };
        aux_count += 1;
        aux_buf[aux_count] = .{ .key = AT_ENTRY, .val = load_base + ehdr.e_entry };
        aux_count += 1;
        aux_buf[aux_count] = .{
                .key = AT_BASE,
                .val = if (interp_binary != null) INTERP_LOAD_BASE else load_base
        };
        aux_count += 1;
    }
    aux_buf[aux_count] = .{ .key = AT_SYSINFO_EHDR, .val = vdso_ehdr_addr };
    aux_count += 1;
    aux_buf[aux_count] = .{ .key = AT_PAGESZ, .val = krn.mm.PAGE_SIZE };
    aux_count += 1;
    aux_buf[aux_count] = .{ .key = AT_NULL, .val = 0 };
    aux_count += 1;

    setEnvironment(
        stack_bottom,
        stack_size,
        argv, envp,
        aux_buf[0..aux_count]
    );

    krn.logger.INFO("Userspace stack: 0x{X:0>8} 0x{X:0>8}", .{stack_bottom, stack_bottom + stack_size});
    final_eip = if (interp_binary != null)
        INTERP_LOAD_BASE + interp_entry
    else
        load_base + ehdr.e_entry;
    krn.logger.INFO("Userspace EIP (_start): 0x{X:0>8}", .{final_eip});

    // Also arch specific
    heap_start = arch.pageAlign(heap_start, false);
    krn.logger.INFO("heap_start 0x{X:0>8}\n", .{heap_start});
    krn.task.current.mm.?.brk_start = heap_start;
    krn.task.current.mm.?.brk = heap_start;
    krn.task.current.mm.?.heap = heap_start + HEAP_MMAP_GAP;
    krn.task.current.mm.?.stack_bottom = stack_bottom;
    krn.task.current.mm.?.stack_top = stack_bottom + stack_size;
    krn.task.current.mm.?.code = final_eip;
    krn.task.current.tsktype = .PROCESS;
}

pub fn goUserspace() void {
    arch.idt.goUserspace();
}
