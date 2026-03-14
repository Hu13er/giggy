const screenWidth: u32 = 800;
const screenHeight: u32 = 600;
const hz = 30;
const first_entity = std.math.maxInt(engine.ecs.Entity) / 2;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // setup
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
    app.world.next_entity = first_entity;

    // engine plugins
    try app.addPlugin(net.Plugin, .{
        .component_registry = comp_reg,
    });

    // game plugins
    try app.addPlugin(game_plugins.core.Plugin, .{
        .width = screenWidth,
        .height = screenHeight,
        .fixed_dt = 1.0 / @as(f32, @floatFromInt(hz)),
    });
    try app.addPlugin(game_plugins.net.Plugin, .{
        .host_type = .server,
    });

    // main loop
    var timer = try time.Timer.start();
    while (true) {
        const since_last = timer.lap();
        const since_last_secs = @as(f32, @floatFromInt(since_last)) / @as(f32, @floatFromInt(time.ns_per_s));
        try app.tick(since_last_secs);

        const used = timer.read();
        const expected = @as(u64, @divTrunc(time.ns_per_s, hz));
        if (used < expected) {
            const to_wait = expected - used;
            sleep(to_wait);
        }
    }
}

const std = @import("std");
const time = std.time;
const sleep = std.Thread.sleep;

const engine = @import("engine");
const core = engine.core;
const net = engine.net;

const game = @import("game");
const game_plugins = game.plugins;
