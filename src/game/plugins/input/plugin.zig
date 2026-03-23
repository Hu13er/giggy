pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.PlayerInput, try .init(app.gpa));
        try app.addSystem(.fixed_update, systems.hardwareInputSystem, .{
            .provides = &.{"input"},
        });
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const game = @import("game");
const resources = game.plugins.input.resources;
const systems = game.plugins.input.systems;
