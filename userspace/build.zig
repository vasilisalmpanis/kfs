const std = @import("std");
const builtin = @import("builtin");

const name = "user.bin";
const linker = "linker.ld";
const src = "src/main.zig";

const archs = [_]std.Target.Cpu.Arch{
    std.Target.Cpu.Arch.x86,
};

pub fn build(b: *std.Build) !void {
    for (archs) |arch| {
        var target: std.Target.Query = .{
            .cpu_arch = arch,
            .os_tag = .freestanding,
            .abi = .none
        };
        const Features = std.Target.x86.Feature;
        target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
        target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
        target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
        const main = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(src),
            .target = b.resolveTargetQuery(target),
            .optimize = b.standardOptimizeOption(.{}),
            .code_model = .small,
            .strip = false,
            .error_tracing = false,
            .link_libc = false,
        });
        main.root_module.stack_protector = false;
        main.root_module.stack_check = false;
        main.root_module.red_zone = false;
        main.entry = std.Build.Step.Compile.Entry.disabled;
        main.setLinkerScript(b.path(linker));

        b.installArtifact(main);

        const main_step = b.step(name, "Build userspace");
        main_step.dependOn(&main.step);
    }
}
