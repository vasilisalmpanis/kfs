const printf = @import("./printf.zig").printf;
const mm = @import("kernel").mm;
const print_free_list = @import("./mm.zig").print_free_list;

pub fn run_tests() void {
    var i: u32 = 0;
    var j: u32 = 0;
    // fails at size 312
    // const size: u32 = 312;
    const size: u32 = 511;
    var arr: [size]u32 = .{0} ** size;
    while (i < 2) : (i += 1) {
        j = 0;
        while (j < size) : (j += 1) {
            arr[j] = mm.kmalloc(0);
            // if (arr[j] - 8 == 0xC1001000)
                // print_free_list();
                // printf("{d} addr: {x}\n", .{j, arr[j] - 8});
        }
            // printf("addr: {x}\n", .{arr[j]});
        // print_free_list();
        j = 0;
        while (j < size) : (j += 1) {

            // if (arr[j] - 8 == 0xC1001000)
                // print_free_list();
            // printf("addr: {x}\n", .{arr[j]});
            mm.kfree(arr[j]);
            // if (arr[j] - 8 == 0xC1001000)
                // print_free_list();
        }
    }
    print_free_list();
}
