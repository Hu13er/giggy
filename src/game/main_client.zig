const screenWidth: u32 = 800;
const screenHeight: u32 = 600;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // setup
    rl.InitWindow(screenWidth, screenHeight, "Giggy: Echoes of the Hollow");
    defer rl.CloseWindow();
    const hz = rl.GetMonitorRefreshRate(rl.GetCurrentMonitor());
    rl.SetTargetFPS(hz);

    var comp_reg = try engine.ecs.ComponentRegistry.init(allocator);
    // BUG: this causes panic: interger overflow.
    // defer comp_reg.deinit();
    const comps_count = try comp_reg.registerAllComponents(&[_]type{
        game.components.animation,
        game.components.collision,
        game.components.enemy,
        game.components.player,
        game.components.render,
        game.components.transform,
        game.components.world,
    });
    std.debug.print("[!] Registered {d} components\n", .{comps_count});

    var app = try core.App.init(allocator);
    defer app.deinit();

    // engine plugins
    try app.addPlugin(AssetsPlugin, .{});
    try app.addPlugin(PrefabPlugin, .{});
    try app.addPlugin(NetPlugin, .{
        .component_registry = comp_reg,
    });

    // game plugins
    try app.addPlugin(game_plugins.core.Plugin, .{
        .width = screenWidth,
        .height = screenHeight,
        .fixed_dt = 1.0 / 60.0,
    });
    try app.addPlugin(game_plugins.debug.Plugin, .{});
    try app.addPlugin(game_plugins.assets.Plugin, .{});
    try app.addPlugin(game_plugins.render.Plugin, .{});
    try app.addPlugin(game_plugins.physics.Plugin, .{});
    try app.addPlugin(game_plugins.input.Plugin, .{});
    try app.addPlugin(game_plugins.player.Plugin, .{});
    try app.addPlugin(game_plugins.enemy.Plugin, .{});
    try app.addPlugin(game_plugins.camera.Plugin, .{
        .width = screenWidth,
        .height = screenHeight,
    });
    try app.addPlugin(game_plugins.level.Plugin, .{});
    try app.addPlugin(game_plugins.fade.Plugin, .{});
    try app.addPlugin(game_plugins.net.Plugin, .{
        .host_type = .client,
    });

    // main loop
    while (!rl.WindowShouldClose()) {
        const frame_dt = rl.GetFrameTime();
        app.tick(frame_dt) catch |e| {
            std.debug.print("got error: {t}", .{e});
            return e;
        };
    }
}

const std = @import("std");
const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
const AssetsPlugin = engine.assets.Plugin;
const PrefabPlugin = engine.prefabs.Plugin;
const NetPlugin = engine.net.Plugin;

const game = @import("game");
const game_plugins = game.plugins;
