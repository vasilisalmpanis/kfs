const smp = @import("main.zig");
const krn = @import("kernel");

pub extern const _percpu_start: u32;
pub extern const _percpu_end: u32;

pub var percpu_start_addr: u32 = undefined;
pub var percpu_end_addr: u32 = undefined;

pub var percpu_mem_addr: u32 = undefined;
pub var percpu_curr_addr: u32 = undefined;
pub var percpu_size_aligned: u32 = undefined;
pub var percpu_size: u32 = undefined;

pub inline fn thisCpuBase() usize {
    return asm volatile (
        \\ mov %%gs:0, %[ret]
        : [ret] "=r" (-> usize)
    );
}

pub fn PerCpu(comptime T: type, comptime init: T, comptime _: type) type {
    return struct {
        var value: T linksection(".percpu.data") = init;

        pub inline fn ptr() *T {
            // TODO: think about preemption
            const offset = @intFromPtr(&value) - @intFromPtr(&_percpu_start);
            return @ptrFromInt(thisCpuBase() + offset);
        }

        /// Works only with scalar types
        pub inline fn get() T {
            const offset = @intFromPtr(&value) - @intFromPtr(&_percpu_start);
            return asm volatile (
                \\ mov %%gs:(%[offset]), %[ret]
                \\
                : [ret] "=r" (-> T)
                : [offset] "r" (offset),
                : .{ .memory = true }
            );
        }

        /// Works only with scalar types
        pub inline fn set(v: T) void {
            const offset = @intFromPtr(&value) - @intFromPtr(&_percpu_start);
            asm volatile (
                \\ mov %[val], %%gs:(%[offset])
                \\
                :: [val] "r" (v),
                   [offset] "r" (offset),
                : .{ .memory = true }
            );
        }

        pub inline fn ptrOn(cpu: u32) *T {
            _ = cpu;
        }

        pub inline fn ptrFromBase(base: u32) *T {
            // TODO: think about preemption
            const offset = @intFromPtr(&value) - @intFromPtr(&_percpu_start);
            return @ptrFromInt(base + offset);
        }

        /// Use only in BSP core
        pub inline fn getRawPtr() *T {
            return &value;
        } 
    };
}

pub fn initPerCPUMemory() !void {
    if (smp.cpu_count == 1)
        return ;
    percpu_size = percpu_end_addr - percpu_start_addr;
    percpu_size_aligned = if (percpu_size % 64 == 0)
        percpu_size
    else
        percpu_size + (64 - percpu_size % 64);
    const total_size = percpu_size_aligned * (smp.cpu_count - 1);
    const percpu_mem = krn.mm.kmallocArray(u8, total_size + 63) orelse
        return krn.errors.PosixError.ENOMEM;
    percpu_mem_addr = @intFromPtr(percpu_mem);

    if (percpu_mem_addr % 64 != 0)
        percpu_mem_addr += (64 - percpu_mem_addr % 64);
    percpu_curr_addr = percpu_mem_addr;
    const orig_percpu_mem: [*]u8 = @ptrFromInt(percpu_start_addr);
    var offset: u32 = 0;
    for (0..smp.cpu_count - 1) |_| {
        const dest_addr = percpu_mem_addr + offset;
        const dest: [*]u8 = @ptrFromInt(dest_addr);
        @memcpy(dest[0..percpu_size], orig_percpu_mem[0..percpu_size]);
        const curr_percpu_addr: *u32 = @ptrFromInt(dest_addr);
        curr_percpu_addr.* = dest_addr;
        offset += percpu_size_aligned;
    }
}
