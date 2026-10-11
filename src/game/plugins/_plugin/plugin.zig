pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.SampleResource, .init(app.gpa));
        try app.addSystem(.fixed_update, systems.sampleSystem, .{});
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;

const game = @import("game");
const components = game.components;
const systems = game.plugins._plugin.systems;
const resources = game.plugins._plugin.resources;
