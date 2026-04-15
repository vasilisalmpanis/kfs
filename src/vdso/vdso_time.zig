const VdsoData = extern struct {
    seq: u32,
    monotonic_sec: i32,
    monotonic_nsec: i32,
    realtime_sec: i64,
    realtime_nsec: i32,
    _pad: i32,
};

const kernel_timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,
};

const kernel_timespec64 = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

const CLOCK_REALTIME: u32 = 0;
const CLOCK_MONOTONIC: u32 = 1;
const PAGE_MASK: u32 = 0xFFFFF000;
const EINVAL: i32 = 22;

inline fn getVvarData() *const volatile VdsoData {
    // Get current PC
    const pc = asm volatile (
        \\call 1f
        \\1: pop %[ret]
        : [ret] "=r" (-> u32),
    );
    // Page-align to get the vDSO code page base, then subtract one page for vvar
    const vvar_addr = (pc & PAGE_MASK) - 0x1000;
    return @ptrFromInt(vvar_addr);
}

export fn __vdso_clock_gettime(clock_id: u32, tp: ?*kernel_timespec) i32 {
    const out = tp orelse return -EINVAL;
    const vvar = getVvarData();

    while (true) {
        var seq1 = vvar.seq;
        while (seq1 & 1 != 0) {
            seq1 = vvar.seq;
        }
        asm volatile ("" ::: .{ .memory = true });

        switch (clock_id) {
            CLOCK_MONOTONIC => {
                out.tv_sec = vvar.monotonic_sec;
                out.tv_nsec = vvar.monotonic_nsec;
            },
            CLOCK_REALTIME => {
                out.tv_sec = @truncate(vvar.realtime_sec);
                out.tv_nsec = vvar.realtime_nsec;
            },
            else => return -1,
        }

        asm volatile ("" ::: .{ .memory = true });
        const seq2 = vvar.seq;
        if (seq1 == seq2) {
            return 0;
        }
    }
}

export fn __vdso_clock_gettime64(clock_id: u32, tp: ?*kernel_timespec64) i32 {
    const out = tp orelse return -EINVAL;
    const vvar = getVvarData();

    while (true) {
        var seq1 = vvar.seq;
        while (seq1 & 1 != 0) {
            seq1 = vvar.seq;
        }
        asm volatile ("" ::: .{ .memory = true });

        switch (clock_id) {
            CLOCK_MONOTONIC => {
                out.tv_sec = vvar.monotonic_sec;
                out.tv_nsec = vvar.monotonic_nsec;
            },
            CLOCK_REALTIME => {
                out.tv_sec = @truncate(vvar.realtime_sec);
                out.tv_nsec = vvar.realtime_nsec;
            },
            else => return -1,
        }

        asm volatile ("" ::: .{ .memory = true });
        const seq2 = vvar.seq;
        if (seq1 == seq2) {
            return 0;
        }
    }
}
