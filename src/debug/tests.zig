const printf = @import("./printf.zig").printf;
const mm = @import("kernel").mm;
const print_free_list = @import("./mm.zig").print_free_list;

pub fn run_tests() void {
    var i: u32 = 0;
    var j: u32 = 0;
    const size: u32 = 1000;
    var arr: [size]u32 = .{0} ** size;
    while (i < 2) : (i += 1) {
        j = 0;
        while (j < size) : (j += 1) {
            arr[j] = mm.kmalloc(j);
        }
        j = 0;
        while (j < size) : (j += 1) {
            mm.kfree(arr[j]);
        }
    }
    print_free_list();
}
