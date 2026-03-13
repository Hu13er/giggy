const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_system_raylib = b.option(
        bool,
        "system-raylib",
        "Use system-installed raylib instead of bundled static lib (auto-detected if not set)",
    ) orelse detectSystemRaylib(b);

    const engine_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_mod.addImport("engine", engine_mod);
    engine_mod.addIncludePath(b.path("third_party/enet/include/"));
    engine_mod.addIncludePath(b.path("third_party/raylib/include/"));

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/game/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_mod.addImport("engine", engine_mod);
    game_mod.addImport("game", game_mod);

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/game/main_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    server_mod.addImport("engine", engine_mod);
    server_mod.addImport("game", game_mod);

    const server_exe = b.addExecutable(.{
        .name = "giggy-server",
        .root_module = server_mod,
    });
    server_exe.linkLibC();

    server_exe.addIncludePath(b.path("third_party/raylib/include/"));
    server_exe.addObjectFile(b.path("third_party/enet/lib/libenet.a"));
    if (use_system_raylib) {
        server_exe.linkSystemLibrary("raylib");
    } else {
        server_exe.addObjectFile(b.path("third_party/raylib/lib/libraylib.a"));
    }
    b.installArtifact(server_exe);

    const server_cmd = b.addRunArtifact(server_exe);
    server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        server_cmd.addArgs(args);
    }

    const server_run_step = b.step("run-server", "Run the app");
    server_run_step.dependOn(&server_cmd.step);

    const client_mod = b.createModule(.{
        .root_source_file = b.path("src/game/main_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_mod.addImport("engine", engine_mod);
    client_mod.addImport("game", game_mod);

    const client_exe = b.addExecutable(.{
        .name = "giggy-client",
        .root_module = client_mod,
    });
    client_exe.linkLibC();

    client_exe.addIncludePath(b.path("third_party/enet/include/"));
    client_exe.addObjectFile(b.path("third_party/enet/lib/libenet.a"));

    client_exe.addIncludePath(b.path("third_party/raylib/include/"));
    if (use_system_raylib) {
        client_exe.linkSystemLibrary("raylib");
    } else {
        client_exe.addObjectFile(b.path("third_party/raylib/lib/libraylib.a"));
    }
    b.installArtifact(client_exe);

    const client_cmd = b.addRunArtifact(client_exe);
    client_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        client_cmd.addArgs(args);
    }

    const client_run_step = b.step("run-client", "Run the app");
    client_run_step.dependOn(&client_cmd.step);

    const examples_step = b.step("examples", "Build all examples");
    addExample(b, engine_mod, target, optimize, use_system_raylib, "blob", "src/examples/blob/main.zig", examples_step);
    addExample(b, engine_mod, target, optimize, use_system_raylib, "ecs-stress", "src/examples/ecs_stress/main.zig", examples_step);
    addExample(b, engine_mod, target, optimize, use_system_raylib, "path-finding", "src/examples/path_finding/main.zig", examples_step);
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

fn addExample(
    b: *std.Build,
    engine_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system_raylib: bool,
    name: []const u8,
    root_path: []const u8,
    examples_step: *std.Build.Step,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path(root_path),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("engine", engine_mod);

    const exe = b.addExecutable(.{
        .name = b.fmt("example-{s}", .{name}),
        .root_module = mod,
    });
    exe.linkLibC();

    exe.addIncludePath(b.path("third_party/raylib/include/"));
    if (use_system_raylib) {
        exe.linkSystemLibrary("raylib");
    } else {
        exe.addObjectFile(b.path("third_party/raylib/lib/libraylib.a"));
    }

    b.installArtifact(exe);

    const build_step = b.step(b.fmt("example-{s}", .{name}), "Build example");
    build_step.dependOn(&exe.step);
    examples_step.dependOn(&exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step(b.fmt("run-example-{s}", .{name}), "Run example");
    run_step.dependOn(&run_cmd.step);
}
