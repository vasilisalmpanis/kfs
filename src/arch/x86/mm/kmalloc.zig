const mm = @import("memory.zig");
const head = @import("./heap.zig");

/// kmalloc - allocate memory
/// size:
///     how many bytes of memory are required.
pub fn kmalloc(size: u32) u32 {
    const virt_addr: u32 = head.alloc(size);
    return virt_addr;
}
 
