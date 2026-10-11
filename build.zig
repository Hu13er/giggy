const std = @import("std");

pub fn build(b: *std.Build) void {
    const name = "giggy";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const detected_raylib = detectSystemRaylib(b);
    const use_system_raylib = b.option(
        bool,
        "system-raylib",
        "Use system-installed raylib instead of bundled static lib (auto-detected if not set)",
    ) orelse (detected_raylib != null);

    const raylib_include_dir = if (use_system_raylib) blk: {
        if (detected_raylib) |raylib| {
            if (raylib.include_dir) |include_dir| break :blk include_dir;
        }
        break :blk null;
    } else null;
    const raylib_header = if (raylib_include_dir) |include_dir|
        std.Build.LazyPath{ .cwd_relative = b.pathJoin(&.{ include_dir, "raylib.h" }) }
    else
        b.path("third_party/raylib/include/raylib.h");
    const raymath_header = if (raylib_include_dir) |include_dir|
        std.Build.LazyPath{ .cwd_relative = b.pathJoin(&.{ include_dir, "raymath.h" }) }
    else
        b.path("third_party/raylib/include/raymath.h");

    const raylib_translate = b.addTranslateC(.{
        .root_source_file = raylib_header,
        .target = target,
        .optimize = optimize,
    });
    const raymath_translate = b.addTranslateC(.{
        .root_source_file = raymath_header,
        .target = target,
        .optimize = optimize,
    });
    if (raylib_include_dir) |include_dir| {
        const include_path = std.Build.LazyPath{ .cwd_relative = include_dir };
        raylib_translate.addSystemIncludePath(include_path);
        raymath_translate.addSystemIncludePath(include_path);
    } else {
        raylib_translate.addIncludePath(b.path("third_party/raylib/include/"));
        raymath_translate.addIncludePath(b.path("third_party/raylib/include/"));
    }

    const engine_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_mod.addImport("engine", engine_mod);
    engine_mod.addImport("raylib_c", raylib_translate.createModule());
    engine_mod.addImport("raymath_c", raymath_translate.createModule());
    if (!use_system_raylib) {
        engine_mod.addIncludePath(b.path("third_party/raylib/include/"));
    } else if (raylib_include_dir) |include_dir| {
        engine_mod.addSystemIncludePath(.{ .cwd_relative = include_dir });
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/game/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("engine", engine_mod);
    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/game/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_mod.addImport("engine", engine_mod);
    game_mod.addImport("game", game_mod);
    exe_mod.addImport("game", game_mod);

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });

    if (use_system_raylib) {
        linkSystemRaylib(exe.root_module, detected_raylib);
    } else {
        exe.root_module.addIncludePath(b.path("third_party/raylib/include/"));
        exe.root_module.addObjectFile(b.path("third_party/raylib/lib/libraylib.a"));
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const examples_step = b.step("examples", "Build all examples");
    addExample(b, engine_mod, target, optimize, use_system_raylib, detected_raylib, "blob", "src/examples/blob/main.zig", examples_step);
    addExample(b, engine_mod, target, optimize, use_system_raylib, detected_raylib, "ecs-stress", "src/examples/ecs_stress/main.zig", examples_step);
    addExample(b, engine_mod, target, optimize, use_system_raylib, detected_raylib, "path-finding", "src/examples/path_finding/main.zig", examples_step);
}

const SystemRaylib = struct {
    include_dir: ?[]const u8,
    library_dir: ?[]const u8,
    use_pkg_config: bool,
};

fn detectSystemRaylib(b: *std.Build) ?SystemRaylib {
    if (runCommand(b, &.{ "brew", "--prefix", "raylib" })) |prefix| {
        const trimmed_prefix = std.mem.trim(u8, prefix, " \r\n\t");
        if (trimmed_prefix.len != 0) {
            return .{
                .include_dir = b.pathJoin(&.{ trimmed_prefix, "include" }),
                .library_dir = b.pathJoin(&.{ trimmed_prefix, "lib" }),
                .use_pkg_config = false,
            };
        }
    }

    if (runCommand(b, &.{ "pkg-config", "--exists", "raylib" }) == null) return null;
    const include_dir = runCommand(b, &.{ "pkg-config", "--variable=includedir", "raylib" });
    const library_dir = runCommand(b, &.{ "pkg-config", "--variable=libdir", "raylib" });
    return .{
        .include_dir = if (include_dir) |dir| std.mem.trim(u8, dir, " \r\n\t") else null,
        .library_dir = if (library_dir) |dir| std.mem.trim(u8, dir, " \r\n\t") else null,
        .use_pkg_config = true,
    };
}

fn runCommand(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = argv,
    }) catch return null;
    defer b.allocator.free(result.stdout);
    defer b.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| {
            if (code != 0) return null;
            return b.allocator.dupe(u8, result.stdout) catch @panic("OOM");
        },
        else => return null,
    }
}

fn linkSystemRaylib(module: *std.Build.Module, raylib: ?SystemRaylib) void {
    if (raylib) |installation| {
        if (installation.library_dir) |library_dir| {
            if (!installation.use_pkg_config) {
                module.addLibraryPath(.{ .cwd_relative = library_dir });
            }
        }
        module.linkSystemLibrary("raylib", .{
            .use_pkg_config = if (installation.use_pkg_config) .yes else .no,
        });
    } else {
        module.linkSystemLibrary("raylib", .{});
    }
}

fn addExample(
    b: *std.Build,
    engine_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system_raylib: bool,
    detected_raylib: ?SystemRaylib,
    name: []const u8,
    root_path: []const u8,
    examples_step: *std.Build.Step,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path(root_path),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("engine", engine_mod);

    const exe = b.addExecutable(.{
        .name = b.fmt("example-{s}", .{name}),
        .root_module = mod,
    });

    if (use_system_raylib) {
        linkSystemRaylib(exe.root_module, detected_raylib);
    } else {
        exe.root_module.addIncludePath(b.path("third_party/raylib/include/"));
        exe.root_module.addObjectFile(b.path("third_party/raylib/lib/libraylib.a"));
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
