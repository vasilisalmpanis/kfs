const printf = @import("./printf.zig").printf;
const mm = @import("kernel").mm;
const printFreeList = @import("./mm.zig").printFreeList;

pub fn runTests() void {
    var i: u32 = 0;
    var j: u32 = 0;

    printf("Tests are running...\n", .{});
    const size: u32 = 10000;
    var arr: [size]?*u32 = .{null} ** size;
    printFreeList();
    while (i < 1) : (i += 1) {
        j = 0;
        while (j < size) : (j += 1) {
            arr[j] = mm.kmalloc(u32);
        }
        printf("Lets free...\n", .{});
        j = 0;
        while (j < size) : (j += 1) {
            if (arr[j] != null)
                mm.kfree(arr[j].?);
        }
    }
    printf("Tests are done...\n", .{});
    printFreeList();
}
