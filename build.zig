const std = @import("std");
const builtin = @import("builtin");

const name = "kfs.bin";
const linker = "linker.ld";
const kernel_src = "src/kernel/main.zig";

const archs = [_]std.Target.Cpu.Arch{
    std.Target.Cpu.Arch.x86,
    // std.Target.Cpu.Arch.x86_64,
};

pub fn build(b: *std.Build) !void {
    for (archs) |arch| {
        const arch_path = switch (arch) {
            std.Target.Cpu.Arch.x86 => "./src/arch/x86/main.zig",
            else => continue
        };

        const arch_mod = b.addModule("arch", .{
            .root_source_file =  b.path(arch_path)
        });
        const drivers = b.addModule("drivers", .{
            .root_source_file =  b.path("./src/drivers/main.zig")
        });
        drivers.addImport("arch", arch_mod);

        var target: std.Target.Query = .{ .cpu_arch = arch, .os_tag = .freestanding, .abi = .none };
        const Features = std.Target.x86.Feature;
        target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
        target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
        const kernel = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(kernel_src),
            .target = b.resolveTargetQuery(target),
            .optimize = b.standardOptimizeOption(.{}),
            .code_model = .kernel,
            .strip = false,
        });
        kernel.root_module.stack_protector = false;
        kernel.root_module.stack_check = false;
        kernel.root_module.red_zone = false;
        kernel.entry = std.Build.Step.Compile.Entry.disabled;
        kernel.root_module.addImport("arch", arch_mod);
        kernel.root_module.addImport("drivers", drivers);

        kernel.setLinkerScriptPath(b.path(linker));
        // kernel.setVerboseLink(true);
        b.installArtifact(kernel);

        const kernel_step = b.step(name, "Build the kernel");
        kernel_step.dependOn(&kernel.step);
    }
}
