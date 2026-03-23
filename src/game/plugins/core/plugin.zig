pub const Plugin = struct {
    width: u32,
    height: u32,
    fixed_dt: f32,
    is_server: bool,

    pub fn build(self: @This(), app: *core.App) !void {
        const time = app.getResource(core.Time).?;
        time.dt = 0;
        time.fixed_dt = self.fixed_dt;
        time.alpha = 0;
        app.setFixedDelta(self.fixed_dt);

        _ = try app.insertResource(resources.IsServer, .{
            .value = self.is_server,
        });

        _ = try app.insertResource(resources.Screen, .{
            .width = self.width,
            .height = self.height,
        });
    }
};
const engine = @import("engine");
const core = engine.core;

const resources = @import("resources.zig");
