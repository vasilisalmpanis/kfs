pub var page_directory: [1024]u32 align(4096) = undefined;
var first_page_table: [1024]u32 align(4096) = undefined;

pub fn reset_page_directory() void {
    var index: u32 = 0;
    while (index < 1024) : (index += 1) {
        page_directory[index] = 0x00000001;
    }
}

pub fn set_first_page() void {
    var index: u32 = 0;
    while (index < 1024) : (index += 1) {
        // Identity map first 4MB
        first_page_table[index] = (index * 0x1000) | 3;  // Present + R/W
    }

    const pt_addr : usize = @intFromPtr(&first_page_table);
    page_directory[0] = pt_addr | 3;  // Present + R/W
}

pub fn load_page_directory(ptr: *u32) void {
    asm volatile (
        \\mov %[ptr], %%eax
        \\mov %%eax, %%cr3
        :
        : [ptr] "r" (ptr)
        : "eax"
    );
}

pub fn enable_paging() void {
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: "eax" 
    );
}

pub fn disable_perms() void {
    asm volatile (
        \\ mov     %cr0, %eax       
        \\ and     $0xFFFFDFFF, %eax 
        \\ mov     %eax, %cr0         
    );
}

pub fn verify_paging() void {
    var cr0: u32 = undefined;
    asm volatile ("mov %%cr0, %[cr0]"
        : [cr0] "=r" (cr0)
    );

    if ((cr0 & (1 << 31)) == 0) {
        @panic("Paging is not enabled!");
    }
}
