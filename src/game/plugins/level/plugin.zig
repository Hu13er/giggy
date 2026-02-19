pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;

        _ = try app.insertResource(resources.RoomManager, .init(app.gpa));

        const registry = app.getResource(engine_prefabs.Registry).?;
        try registry.register("map", prefabs.PrefabsFactory.mapFactory);
        try registry.register("spawn_point", prefabs.PrefabsFactory.spawnPointFactory);
        try registry.register("door", prefabs.PrefabsFactory.doorFactory);
        try registry.register("layer", prefabs.PrefabsFactory.layerFactory);
        try registry.register("edge", prefabs.PrefabsFactory.edgeFactory);

        try app.addSystem(.startup, systems.levelSystem, .{
            .id = "level.setup",
            .provides = &.{"level"},
        });
        try app.addSystem(.startup, systems.walkableSystem, .{
            .after_ids = &.{"level.setup"},
            .provides = &.{"level"},
        });
        try app.addSystem(.fixed_update, systems.doorSystem, .{
            .id = "door.system",
            .after_all_labels = &.{"physics"},
        });
    }
};

const engine = @import("engine");
const core = engine.core;
const engine_prefabs = engine.prefabs;

const resources = @import("resources.zig");
const prefabs = @import("prefabs.zig");
const systems = @import("systems.zig");
