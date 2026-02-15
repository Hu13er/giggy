pub const CorePlugin = struct {
    width: u32,
    height: u32,
    fixed_dt: f32 = 1.0 / 60.0,

    pub fn build(self: @This(), app: *core.App) !void {
        const time = app.getResource(core.Time).?;
        time.dt = 0;
        time.fixed_dt = self.fixed_dt;
        time.alpha = 0;
        app.setFixedDelta(self.fixed_dt);

        _ = try app.insertResource(resources.Screen, .{
            .width = self.width,
            .height = self.height,
        });

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

        var render_targets = try resources.RenderTargets.init(app.gpa);
        errdefer render_targets.deinit();
        _ = try app.insertResource(resources.RenderTargets, render_targets);

        var renderables = try resources.Renderables.init(app.gpa);
        errdefer renderables.deinit();
        _ = try app.insertResource(resources.Renderables, renderables);

        try app.addSystem(.update, CameraOnObjectSystem);
    }
};

const CameraOnObjectSystem = struct {
    pub const after_all_labels: []const []const u8 = &.{"physics"};

    pub fn run(app: *core.App) !void {
        const time = app.getResource(core.Time).?;
        const player = app.getResource(resources.Player).?.entity;
        const camera_state = app.getResource(resources.CameraState).?;
        const screen = app.getResource(resources.Screen).?;
        const room_mgr = app.getResource(resources.RoomManager).?;
        const pos = app.world.get(comps.PositionView, player).?;

        const w = @as(f32, @floatFromInt(screen.width));
        const h = @as(f32, @floatFromInt(screen.height));

        var x = xmath.lerp(pos.prev_x.*, pos.x.*, time.alpha);
        var y = xmath.lerp(pos.prev_y.*, pos.y.*, time.alpha);
        if (room_mgr.current) |room| {
            if (room_mgr.getBounds(room)) |bounds| {
                const half_w = w / 2.0;
                const min_x = bounds.x + half_w;
                const max_x = bounds.x + bounds.w - half_w;
                x = if (max_x < min_x) bounds.x + bounds.w / 2.0 else math.clamp(x, min_x, max_x);

                const half_h = h / 2.0;
                const min_y = bounds.y + half_h;
                const max_y = bounds.y + bounds.h - half_h;
                y = if (max_y < min_y) bounds.y + bounds.h / 2.0 else math.clamp(y, min_y, max_y);
            }
        }

        camera_state.camera.target = .{ .x = x, .y = y };
    }
};

const std = @import("std");
const math = std.math;

const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const xmath = engine.math;

const resources = @import("../resources.zig");
const comps = @import("../components.zig");
