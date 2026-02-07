const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_system_raylib = b.option(
        bool,
        "system-raylib",
        "Use system-installed raylib instead of bundled static lib (auto-detected if not set)",
    ) orelse detectSystemRaylib(b);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "giggy",
        .root_module = exe_mod,
    });

    exe.linkLibC();

    if (use_system_raylib) {
        exe.linkSystemLibrary("raylib");
    } else {
        exe.addIncludePath(b.path("include/"));
        exe.addObjectFile(b.path("lib/libraylib.a"));
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

/// Probe pkg-config to see if raylib is installed system-wide.
fn detectSystemRaylib(b: *std.Build) bool {
    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "pkg-config", "--exists", "raylib" },
    }) catch return false;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);
    switch (result.term) {
        .Exited => |code| return code == 0,
        else => return false,
    }
}
