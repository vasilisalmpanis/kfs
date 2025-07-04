const kernel = @import("kernel");


pub export fn test_init() linksection(".init.text") void {
    for (0..10) |id| {
        kernel.logger.INFO("DEVIVE INIT CALL {d}\n", .{id});
    }
}

export var test_g: *const fn() callconv(.c) void linksection(kernel.InitLevel.DEVICE) = test_init;
