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
        first_page_table[index] = (index * 0x1000) | 1;
    }
    page_directory[0] = first_page_table | 1;
}

pub fn load_page_directory(ptr: *u32) void {
    _ = ptr;
    asm volatile(
        \\push %ebp
        \\mov %esp, %ebp
        \\mov 8(%esp), %eax
        \\mov %eax, %cr3
        \\mov %ebp, %esp
        \\pop %ebp
    );
}

pub fn enable_paging() void {
    asm volatile (
        \\push %ebp
        \\mov %esp, %ebp
        \\mov %cr0, %eax
        \\or $0x80000000, %eax
        \\mov %eax, %cr0
        \\mov %ebp, %esp
        \\pop %ebp
    );
    disable_perms();
}

pub fn disable_perms() !void {
    asm volatile (
        \\ mov     %cr0, %eax       
        \\ and     $0xFFFFDFFF, %eax 
        \\ mov     %eax, %cr0         
    );
}
