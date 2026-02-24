pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        app.insertResource(resources.PlayerInput, .{});
        try app.addSystem(.update, systems.playerInputSystem, .{
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
