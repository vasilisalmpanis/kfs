const printf = @import("drivers").printf;
const PMM = @import("./pmm.zig").PMM;

const PAGE_PRESENT: u8 = 0x1;
const PAGE_WRITE: u8 = 0x2;
const PAGE_4MB: u8 = 0x80;

fn print_page_dir() void {
   var index: u32 = 3;
   while (index < 768) : (index += 1) {
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

pub fn print_page_table(virtual_addr: u32) void {
    const pd_index = virtual_addr >> 22;          // Page directory index
    const page_table_addr = initial_page_dir[pd_index] & 0xFFFFF000;
    
    if (page_table_addr == 0) {
        printf("No page table exists for address 0x{x}\n", .{virtual_addr});
        return;
    }
    
    const page_table: [*]u32 = @ptrFromInt(page_table_addr);
    
    printf("Page Table for Address 0x{x} (Page Directory Index: {d}):\n", .{virtual_addr, pd_index});
    
    for (0..1024) |i| {
        if (page_table[i] != 0) {
            const flags = page_table[i] & 0xFFF;
            printf("  Entry {d}: Physical Addr: 0x{x}, Flags:\n", .{i, page_table[i] & 0xFFFFF000});

            printf("    Present:       {s}\n", .{if (flags & 1 != 0) "Yes" else "No"});
            printf("    Writable:      {s}\n", .{if (flags & 2 != 0) "Yes" else "No"});
            printf("    User/Supervisor: {s}\n", .{if (flags & 4 != 0) "User" else "Supervisor"});
            printf("    Write-Through:  {s}\n", .{if (flags & 8 != 0) "Enabled" else "Disabled"});
            printf("    Cache Disabled: {s}\n", .{if (flags & 16 != 0) "Yes" else "No"});
            printf("    Accessed:      {s}\n", .{if (flags & 32 != 0) "Yes" else "No"});
            printf("    Dirty:         {s}\n", .{if (flags & 64 != 0) "Yes" else "No"});
            printf("    Page Size:     {s}\n", .{if (flags & 128 != 0) "4MB" else "4KB"});
        }
    }
}

pub inline fn InvalidatePage(page: usize) void {
    asm volatile ("invlpg (%eax)"
        :
        : [pg] "{eax}" (page),
    );
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
        // 0x00d00000
        var page_table: [*]u32 = undefined; 
        const pd_index = virtual_addr >> 22;          // Page directory index
        const pt_index = (virtual_addr >> 12) & 0x3FF; // Page table index
        printf("PD_INDEX: {d}\nPT_INDEX: {d}\n",.{pd_index, pt_index});
        var temp: *u8 = undefined;
        // _ = physical_addr;
        // Allocate page table if not exists
        if (initial_page_dir[pd_index] == 0) {
            const new_page_table = self.pmm.alloc_page();
            const new_page_pd_index = (new_page_table >> 20) / 4;
            initial_page_dir[pd_index] = new_page_table | 3; // Present + writable
            initial_page_dir[new_page_pd_index] = PAGE_4MB | PAGE_WRITE | PAGE_PRESENT;
            
            // printf("content {d}\n", .{temp.*});
            page_table = @ptrFromInt(new_page_table & 0xFFFFF000);
            @memset(page_table[0..1024], 0);
        }
        // print_page_dir();
        // // Get page table
        // We are trying access not mapped memory here. We need to understand how to either map it or how to access with recursice mapping
        page_table = @ptrFromInt(initial_page_dir[pd_index] & 0xFFFFF000);
        
        // // Map page table entry
        page_table[pt_index] = physical_addr | 3; // Present + writable
        InvalidatePage(virtual_addr);
        print_page_table(virtual_addr);
        printf("Physical address {x}\n",.{physical_addr});
        temp = @ptrFromInt(virtual_addr); 
        temp.* = 42;    
        printf("temp {d}\n", .{temp.*});
        print_page_table(virtual_addr);
        // printf("content in virtual memory {d}\n", .{temp.*});
    }
};
