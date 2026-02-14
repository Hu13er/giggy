const screenWidth: u32 = 800;
const screenHeight: u32 = 600;

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "Giggy: Echoes of the Hollow");
    defer rl.CloseWindow();
    const hz = rl.GetMonitorRefreshRate(rl.GetCurrentMonitor());
    rl.SetTargetFPS(hz);

    const allocator = std.heap.c_allocator;

    var app = try core.App.init(allocator);
    defer app.deinit();

    try app.addPlugin(AssetsPlugin, .{});
    try app.addPlugin(PrefabPlugin, .{});

    try app.addPlugin(game_plugins.core.CorePlugin, .{
        .width = screenWidth,
        .height = screenHeight,
        .fixed_dt = 1.0 / 60.0,
    });
    try app.addPlugin(game_plugins.assets.AssetsPlugin, .{});
    try app.addPlugin(game_plugins.physics.PhysicsPlugin, .{});
    try app.addPlugin(game_plugins.player.PlayerPlugin, .{});
    try app.addPlugin(game_plugins.level.LevelPlugin, .{
        .file_path = "tiled/objects.tmj",
    });
    try app.addPlugin(game_plugins.render.RenderPlugin, .{});

    while (!rl.WindowShouldClose()) {
        const frame_dt = rl.GetFrameTime();
        try app.tick(frame_dt);
    }
}

const std = @import("std");
const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const AssetsPlugin = engine.assets.Plugin;
const PrefabPlugin = engine.prefabs.Plugin;

const game_plugins = @import("plugins.zig");
