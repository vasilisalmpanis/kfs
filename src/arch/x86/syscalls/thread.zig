const krn = @import("kernel");
const tsk = krn.task;
const errors = krn.errors.PosixError;
const arch = @import("../main.zig");
const std = @import("std");

const UserDescBits = packed struct(u8) {
    seg_32bit: u1,
    contents: u2,
    read_exec_only: u1,
    limit_in_pages: u1,
    seg_not_present: u1,
    useable: u1,
    lm: u1,
};

// See https://elixir.bootlin.com/linux/v6.19.3/source/arch/x86/include/uapi/asm/ldt.h#L21
pub const UserDesc = extern struct{
    entry_number: i32,
    base_addr: u32,
    limit: u32,
    bits: UserDescBits,
};

pub fn resetTLS(self: *krn.task.Task) void {
    self.tls_entry_number = arch.gdt.GDT_TLS0_INDEX;
    self.tls_selector = arch.idt.USER_DATA_SEGMENT;
    self.tls_access = 0x72;
    self.tls_gran = 0;
}

fn getAccess(bits: UserDescBits) u8 {
    var access: u8 = 0x10 | 0x60;
    if (bits.seg_not_present == 0)
        access |= 0x80;

    if (bits.contents == 2) {
        access |= 0x08;
        if (bits.read_exec_only == 0)
            access |= 0x02;
    } else {
        if (bits.contents == 1)
            access |= 0x04;
        if (bits.read_exec_only == 0)
            access |= 0x02;
    }
    return access;
}

fn getGranularity(bits: UserDescBits) u8 {
    var gran: u8 = 0;
    if (bits.limit_in_pages != 0)
        gran |= 0x80;
    if (bits.seg_32bit != 0)
        gran |= 0x40;
    if (bits.useable != 0)
        gran |= 0x10;
    return gran;
}

pub fn applyTLSDesc(task: *tsk.Task, ptr: *UserDesc) !u16 {
    if (@intFromPtr(ptr) == 0)
        return errors.EFAULT;

    if (ptr.entry_number == -1) {
        ptr.entry_number = @intCast(arch.gdt.GDT_TLS0_INDEX);
    } else if (
        ptr.entry_number < @as(i32, @intCast(arch.gdt.GDT_TLS0_INDEX))
        or ptr.entry_number > @as(i32, @intCast(arch.gdt.GDT_TLS2_INDEX))
    ) {
        return errors.EINVAL;
    }

    const entry_number: u32 = @intCast(ptr.entry_number);
    task.tls = ptr.base_addr;
    task.limit = ptr.limit;
    task.tls_entry_number = entry_number;
    task.tls_selector = if (ptr.bits.seg_not_present == 0)
        @intCast((entry_number << 3) | 0x3)
    else
        0;
    task.tls_access = getAccess(ptr.bits);
    task.tls_gran = getGranularity(ptr.bits);
    return task.tls_selector;
}

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
    const sel = try applyTLSDesc(krn.task.current, ptr);
    arch.gdt.gdt_entries.ptr()[krn.task.current.tls_entry_number].set(
        krn.task.current.tls,
        krn.task.current.limit,
        krn.task.current.tls_access,
        krn.task.current.tls_gran
    );
    const regs: *arch.Regs = @ptrFromInt(arch.gdt.tss.ptr().esp0 - @sizeOf(arch.Regs));
    regs.gs = sel;
    krn.task.current.regs.gs = sel;
    return 0;
}

pub fn set_tid_address(tidptr: u32) !u32 {
    krn.logger.INFO(
        "set_tid_address addr: {x}",
        .{tidptr}
    );
    if (tidptr == 0) {
        tsk.current.clear_tid = null;
    } else {
        tsk.current.clear_tid = @ptrFromInt(tidptr);
    }
    return tsk.current.pid;
}
