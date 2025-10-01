const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = std.Target.Query{
        .cpu_arch = std.Target.Cpu.Arch.x86,
        .os_tag = .freestanding,
        .abi = .none,
    };
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const example_mod = b.addObject(.{
        .name = "example_mod",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./src/root.zig"),
            .code_model = .kernel,
            .link_libc = false,
            .target = b.resolveTargetQuery(target),
            // .strip = false,
            .stack_protector = false,
            .stack_check = false,
            .red_zone = false,
            .error_tracing = false,
            .fuzz = false,
            .optimize = optimize,
            .pic = true,
        }),
    });

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
