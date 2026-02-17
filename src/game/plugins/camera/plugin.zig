pub const Plugin = struct {
    width: u32,
    height: u32,

    pub fn build(self: @This(), app: *core.App) !void {
        const camera = rl.Camera2D{
            .offset = rl.Vector2{
                .x = @as(f32, @floatFromInt(self.width)) / 2.0,
                .y = @as(f32, @floatFromInt(self.height)) / 2.0,
            },
            .target = rl.Vector2{ .x = 0, .y = 0 },
            .rotation = 0.0,
            .zoom = 1.0,
        };
        _ = try app.insertResource(resources.CameraState, .{ .camera = camera });

        try app.addSystem(.update, systems.cameraOnObjectSystem, .{
            .after_all_labels = &.{"physics"},
        });
    }
};

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const resources = @import("resources.zig");
const systems = @import("systems.zig");
