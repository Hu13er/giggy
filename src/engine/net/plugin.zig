pub const Plugin = struct {
    config: ?resources.HostManager.Config = null,

    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.ENetInitializer, try .init());
        _ = try app.insertResource(resources.HostManager, try .init(app.gpa));
        try app.addSystem(.startup, systems.networkInitSystem, .{
            .provides = &.{"network.init"},
        });
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const resources = engine.net.resources;
const systems = engine.net.systems;
