const std = @import("std");

pub fn build(b: *std.Build) void {
    var target = std.Target.Query{
        .cpu_arch = std.Target.Cpu.Arch.x86,
        .os_tag = .freestanding,
        .abi = .none,
    };
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    const example_mod = b.addObject(.{
        .name = "keyboard",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./src/root.zig"),
            .code_model = .kernel,
            .link_libc = false,
            .target = b.resolveTargetQuery(target),
            .strip = true,
            .stack_protector = false,
            .stack_check = false,
            .red_zone = false,
            .error_tracing = true,
            .fuzz = false,
            .optimize = optimize,
        }),
    });

    const kfs = b.dependency("types", .{});
    example_mod.root_module.addImport("kfs", kfs.module("types"));

    const install = b.addInstallArtifact(
        example_mod,
        .{
            .dest_dir =  .{
                .override = .{ .custom = "." }
            },
        }
    );
    b.default_step.dependOn(&install.step);
    example_mod.entry = std.Build.Step.Compile.Entry.disabled;
}
