pub const Plugin = struct {
    serverConfig: ?resources.Server.Config = null,

    pub fn build(self: @This(), app: *core.App) !void {
        try app.insertResource(resources.ENetInitializer, .{});
        if (self.serverConfig) |cfg| {
            try app.insertResource(resources.Server, try .init(cfg));
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
