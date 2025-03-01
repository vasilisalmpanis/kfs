const printf = @import("./printf.zig").printf;
const mm = @import("kernel").mm;
const print_free_list = @import("./mm.zig").print_free_list;

pub fn run_tests() void {
    var i: u32 = 0;
    var j: u32 = 0;

    printf("Tests are running...\n", .{});
    // var ptr: [*]u8 = @ptrFromInt(mm.kmalloc(128 * 1024 * 1024));
    // @memcpy(ptr[0..5], "12345");
    const size: u32 = 15000;
    var arr: [size]u32 = .{0} ** size;
    // var varr: [size]u32 = .{0} ** size;
    print_free_list();
    while (i < 1) : (i += 1) {
        j = size;
        while (j > 0) : (j -= 1) {
            arr[j - 1] = mm.kmalloc(j);
            // varr[j - 1] = mm.vmalloc(j);
        }
        printf("Lets free...\n", .{});
        j = size;
        while (j > 0) : (j -= 1) {
            if (arr[j - 1] == 0) {
                printf("free: {x} at {d}\n", .{arr[j - 1], j - 1});
                continue ;
            }
            mm.kfree(arr[j - 1]);
            // mm.vfree(varr[j - 1]);
        }
    }
    printf("Tests are done...\n", .{});
    print_free_list();
}
