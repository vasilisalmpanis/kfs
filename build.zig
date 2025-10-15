const std = @import("std");
const builtin = @import("builtin");

const name = "kfs.bin";
const linker = "linker.ld";
const kernel_src = "src/main.zig";

const userspace_name = "userspace.bin";

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
        const drivers_mod = b.addModule("drivers", .{
            .root_source_file =  b.path("./src/drivers/main.zig")
        });
        const debug_mod = b.addModule("debug", .{
            .root_source_file =  b.path("./src/debug/main.zig")
        });
        const kernel_mod = b.addModule("kernel", .{
            .root_source_file =  b.path("./src/kernel/main.zig")
        });
        const modules_mod = b.addModule("modules", .{
            .root_source_file =  b.path("./src/module/main.zig")
        });

        drivers_mod.addImport("arch", arch_mod);
        drivers_mod.addImport("debug", debug_mod);
        drivers_mod.addImport("kernel", kernel_mod);

        arch_mod.addImport("debug", debug_mod);
        arch_mod.addImport("kernel", kernel_mod);
        
        debug_mod.addImport("arch", arch_mod);
        debug_mod.addImport("drivers", drivers_mod);
        debug_mod.addImport("kernel", kernel_mod);

        kernel_mod.addImport("arch", arch_mod);
        kernel_mod.addImport("debug", debug_mod);
        kernel_mod.addImport("drivers", drivers_mod);

        modules_mod.addImport("kernel", kernel_mod);
        modules_mod.addImport("arch", arch_mod);
        modules_mod.addImport("debug", debug_mod);
        modules_mod.addImport("drivers", drivers_mod);

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
            .root_module = b.createModule(.{
                .root_source_file = b.path(kernel_src),
                .optimize = b.standardOptimizeOption(.{}),
                .target = b.resolveTargetQuery(target),
                .code_model = .kernel,
                .strip = false,
            }),
        });
        kernel.root_module.stack_protector = false;
        kernel.root_module.stack_check = false;
        kernel.root_module.red_zone = false;
        kernel.entry = std.Build.Step.Compile.Entry.disabled;

        kernel.root_module.addImport("arch", arch_mod);
        kernel.root_module.addImport("drivers", drivers_mod);
        kernel.root_module.addImport("debug", debug_mod);
        kernel.root_module.addImport("kernel", kernel_mod);
        kernel.root_module.addImport("modules", modules_mod);

        kernel.setLinkerScript(b.path(linker));
        kernel.addAssemblyFile(b.path("./src/arch/x86/boot/boot.s"));

        // kernel.setVerboseLink(true);
        b.installArtifact(kernel);

        // Add userspace binary
        // const userspace_bin_path = b.path("./userspace_c/userspace.bin");
        const userspace_bin_path = b.path("./zig-out/bin/userspace.bin");
        target.abi = .musl;
        target.os_tag = .linux;
        const userspace = b.addExecutable(.{
            .name = userspace_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("./userspace/src/main.zig"),
                .target = b.resolveTargetQuery(target),
                .optimize = .ReleaseSmall,
                .code_model = .default,
                .strip = false,
                .error_tracing = false,
                .link_libc = false,
                .single_threaded = true,
            }),
            .linkage = .static,
        });
        userspace.setLinkerScript(b.path("./userspace/linker.ld"));
        b.installArtifact(userspace);

        kernel.root_module.addAnonymousImport("userspace", .{
            .root_source_file = userspace_bin_path,
        });
        kernel.step.dependOn(&userspace.step);

        const kernel_step = b.step(name, "Build the kernel");
        const codegen_step = b.step("gen", "Build module types");



        const codegen = b.addExecutable(.{
            .name = "codegen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/codegen.zig"),
                .target = b.resolveTargetQuery(target),
            }),
        });
        codegen.root_module.addImport("modules", modules_mod);

        const run_codegen = b.addRunArtifact(codegen);
        _ = run_codegen.addOutputFileArg("types.zig");

        // try writeStructs("types.zig");
        codegen_step.dependOn(&run_codegen.step);
        kernel_step.dependOn(&kernel.step);
    }
}
