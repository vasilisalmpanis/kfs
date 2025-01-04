const std = @import("std");
const builtin = @import("builtin");

const name = "kfs.bin";
const linker = "linker.ld";
const multiboot = "src/arch/x86/boot/multiboot.s";
const kernel_src = "src/kernel/main.zig";

const targets: []const std.Target.Query = &.{
    .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none
    },
};

pub fn build(b: *std.Build) void {
    for (targets) |target| {
        const kernel = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(kernel_src),
            .target = b.resolveTargetQuery(target),
            .optimize = b.standardOptimizeOption(.{}),
            .code_model = .kernel,
        });
        kernel.addAssemblyFile(b.path(multiboot));
        kernel.setLinkerScriptPath(b.path(linker));
        b.installArtifact(kernel);

        const kernel_step = b.step(name, "Build the kernel");
        kernel_step.dependOn(&kernel.step);
    }
}
