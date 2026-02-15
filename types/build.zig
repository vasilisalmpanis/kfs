
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
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));

    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("types.zig"),
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
    });
    _ = types_mod;
}
