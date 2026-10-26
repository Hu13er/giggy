pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        try app.addSystem(.startup, systems.enemySpawnerSystem, .{});
        try app.addSystem(.fixed_update, systems.enemyAISystem, .{
            .provides = &.{"input", "ai"},
        });
        try app.addSystem(.update, systems.updateAnimationSystem, .{
            .after_all_labels = &.{"input", "ai"},
        });
    }
};

const engine = @import("engine");
const core = engine.core;
const std = @import("std");
const json = std.json;

const game = @import("game");
const components = game.components;
const level_resources = game.plugins.level.resources;
const render_resources = game.plugins.render.resources;
const systems = game.plugins.ghost.systems;
const resources = game.plugins.ghost.resources;
