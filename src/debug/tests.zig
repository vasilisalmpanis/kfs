const printf = @import("./printf.zig").printf;
const mm = @import("kernel").mm;
const print_free_list = @import("./mm.zig").print_free_list;

pub fn run_tests() void {
    var i: u32 = 0;
    var j: u32 = 0;

    printf("Tests are running...\n", .{});
    const size: u32 = 10000;
    var arr: [size]u32 = .{0} ** size;
    var varr: [size]u32 = .{0} ** size;
    print_free_list();
    while (i < 1) : (i += 1) {
        j = 0;
        while (j < size) : (j += 1) {
            arr[j] = mm.kmalloc(j);
            varr[j] = mm.vmalloc(j);
        }
        printf("Lets free...\n", .{});
        j = 0;
        while (j < size) : (j += 1) {
            if (arr[j] != 0)
                mm.kfree(arr[j]);
            if (varr[j] != 0)
                mm.vfree(varr[j]);
        }
    }
    printf("Tests are done...\n", .{});
    print_free_list();
}
