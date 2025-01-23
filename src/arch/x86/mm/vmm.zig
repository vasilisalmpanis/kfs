const printf = @import("drivers").printf;
const PMM = @import("./pmm.zig").PMM;

fn print_page_dir() void {
   var index: u32 = 0;
   while (index < 3) : (index += 1) {
       const entry = initial_page_dir[index];
       if (entry != 0) {
           const present = (entry & 1) != 0;
           const writable = (entry & 2) != 0;
           const user_accessible = (entry & 4) != 0;
           const write_through = (entry & (1 << 3)) != 0;
           const cache_disabled = (entry & (1 << 4)) != 0;
           const accessed = (entry & (1 << 5)) != 0;
           const dirty = (entry & (1 << 6)) != 0;
           const is_4mb_page = (entry & (1 << 7)) != 0;
           const physical_frame = entry & 0xFFFFF000;

           printf("Index {d}: Raw: 0x{x}\n", .{index, entry});
           printf("  Flags:\n    Present={}, Writable={}, User={}\n    Write-through={}, Cache-disabled={}\n    Accessed={}, Dirty={}, 4MB Page={}\n", 
               .{present, writable, user_accessible, 
                 write_through, cache_disabled, 
                 accessed, dirty, is_4mb_page});
           printf("  Physical Frame: 0x{x}\n", .{physical_frame});
       }
   }
}

extern var initial_page_dir: [1024]u32;
pub const VMM = struct {
    pmm : *PMM,

    pub fn init(pmm: *PMM) VMM {
        const vmm = VMM{.pmm = pmm};
        return vmm;
    }

    // pub fn alloc() u32 {

    // }

    // pub fn free(v_addr: u32) void {

    // }

    pub fn map_page(self: *VMM, virtual_addr: u32, physical_addr: u32) void {
        const pd_index = virtual_addr >> 22;          // Page directory index
        const pt_index = (virtual_addr >> 12) & 0x3FF; // Page table index
        // Allocate page table if not exists
        if (initial_page_dir[pd_index] == 0) {
            const new_page_table = self.pmm.alloc_page();
            initial_page_dir[pd_index] = new_page_table | 3; // Present + writable
        //     // @memset(new_page_table[0..1024], 0);
        //     // @memset(@intToPtr([*]u8, new_page_table), 0, 4096);
        }
        print_page_dir();
        // // Get page table
        // We are trying access not mapped memory here. We need to understand how to either map it or how to access with recursice mapping
        const page_table: [*]u32 = @ptrFromInt(initial_page_dir[pd_index] & 0xFFFFF000);
        
        // // Map page table entry
        page_table[pt_index] = physical_addr | 3; // Present + writable
    }
};
