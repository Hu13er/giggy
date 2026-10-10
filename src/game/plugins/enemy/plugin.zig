pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.ChasePath, .init(app.gpa));
        _ = try app.insertResource(resources.HitMemo, try .init(app.gpa));
        try app.addSystem(.fixed_update, systems.enemySpawnerSystem, .{});
        try app.addSystem(.fixed_update, systems.enemyAISystem, .{
            .provides = &.{"input", "ai"},
        });
        try app.addSystem(.fixed_update, systems.shockwaveHitboxSystem, .{});
        try app.addSystem(.update, systems.shockwaveExpandSystem, .{});
        try app.addSystem(.update, systems.updateAnimationSystem, .{
            .provides = &.{"animation"},
            .after_all_labels = &.{"ai"},
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
const systems = game.plugins.enemy.systems;
const resources = game.plugins.enemy.resources;
