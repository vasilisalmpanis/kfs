const std = @import("std");
const builtin = @import("builtin");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86, .os_tag = .freestanding, .abi = .none },
};

pub fn build(b: *std.Build) void {
    const kernel = b.addExecutable(.{ .name = "kfs.bin", .root_source_file = b.path("src/kernel/main.zig"), .target = b.resolveTargetQuery(targets[0]) });
    kernel.addAssemblyFile(b.path("src/arch/x86/boot/multiboot.s"));
    kernel.setLinkerScriptPath(b.path("linker.ld"));
    b.installArtifact(kernel);
    const kernel_step = b.step("kfs.bin", "Build the kernel");
    kernel_step.dependOn(&kernel.step);
}
