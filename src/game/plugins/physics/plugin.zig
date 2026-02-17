pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        try app.addSystem(.fixed_update, systems.updatePositionsSystem, .{
            .provides = &.{ "movement", "physics" },
            .after_all_labels = &.{"input"},
        });
        try app.addSystem(.fixed_update, systems.updateRotationsSystem, .{
            .provides = &.{ "movement", "physics" },
            .after_all_labels = &.{"input"},
        });
        try app.addSystem(.fixed_update, systems.colliderRigidBodySystem, .{
            .provides = &.{ "collision", "physics" },
            .after_all_labels = &.{"movement"},
        });
    }
};
const engine = @import("engine");
const core = engine.core;

const systems = @import("systems.zig");
