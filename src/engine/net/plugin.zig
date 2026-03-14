pub const Plugin = struct {
    component_registry: engine.ecs.ComponentRegistry,

    pub fn build(self: @This(), app: *core.App) !void {
        _ = try app.insertResource(engine.ecs.ComponentRegistry, self.component_registry);
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
