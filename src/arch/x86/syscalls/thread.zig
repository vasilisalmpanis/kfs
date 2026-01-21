const krn = @import("kernel");
const tsk = krn.task;
const errors = krn.errors.PosixError;
const arch = @import("../main.zig");
const std = @import("std");

const UserDesc = extern struct{
    entry_number: i32,
    base_addr: u32,
    limit: u32,
    seg_32bit: u32,
    contents: u32,
    read_exec_only: u32,
    limit_in_pages: u32,
    seg_not_present: u32,
    useable: u32,
};

pub fn modify_ldt(func: u32, ptr: *UserDesc, size: u32) !u32 {
    krn.logger.INFO(
        "modify_ldt func: {d}, ptr: {any}, size: {x}",
        .{func, ptr, size}
    );
    return errors.ENOSYS;
}

pub fn set_thread_area(ptr: *UserDesc) !u32 {
    krn.logger.INFO(
        "set_thread_area ptr: {any}",
        .{ptr}
    );
    if (ptr.entry_number == -1) {
        ptr.entry_number = arch.gdt.GDT_TLS0_INDEX;
    } else if (ptr.entry_number < arch.gdt.GDT_TLS0_INDEX or ptr.entry_number > arch.gdt.GDT_TLS2_INDEX) {
        return errors.EINVAL;
    }

    const limit: u32 = if (ptr.limit_in_pages != 0)
        ptr.limit
    else 0xFFFFFFFF;

    var access: u8 = 0;
    access |= 0x10; // S=1
    access |= 0x60; // DPL=3
    access |= 0x02; // data, writable
    access |= 0x80; // P=1  (force present, don’t trust user)

    var gran: u8 = 0;
    gran |= 0x80; // G=1 (pages)
    gran |= 0x40; // D=1 (32-bit)
    gran |= 0x10; // AVL=1 (harmless)

    krn.task.current.tls = ptr.base_addr;
    krn.task.current.limit = limit;
    arch.gdt.gdtSetEntry(
        @intCast(ptr.entry_number),
        ptr.base_addr,
        limit,
        access,
        gran
    );
    const sel: u16 = @intCast((ptr.entry_number << 3) | 0x3);
    asm volatile (
        "mov %[_sel], %gs"
        :: [_sel]"r"(sel)
        : .{ .memory = true}
    );
    return 0;
}

pub fn set_tid_address(tidptr: u32) !u32 {
    krn.logger.INFO(
        "set_tid_address addr: {x}",
        .{tidptr}
    );
    return 0;
}
