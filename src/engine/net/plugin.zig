pub const Plugin = struct {
    config: ?resources.HostManager.Config = null,

    pub fn build(self: @This(), app: *core.App) !void {
        try app.insertResource(resources.ENetInitializer, .{});
        if (self.config) |cfg| {
            try app.insertResource(resources.HostManager, try .init(cfg));
            try app.addSystem(.startup, systems.networkInit, .{
                .provides = &.{"network.init"},
            });
        }
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const resources = engine.net.resources;
const systems = engine.net.systems;
