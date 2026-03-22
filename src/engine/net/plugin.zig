pub const Plugin = struct {
    component_registry: engine.ecs.ComponentRegistry,

    pub fn build(self: @This(), app: *core.App) !void {
        var comp_reg = try app.insertResource(engine.ecs.ComponentRegistry, self.component_registry);
        try comp_reg.register(engine.net.Sync);

        _ = try app.insertResource(resources.ENetInitializer, try .init());
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
