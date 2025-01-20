extern var initial_page_dir: [1024]u32;

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
