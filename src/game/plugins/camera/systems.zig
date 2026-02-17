pub fn cameraOnObjectSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const player = app.getResource(player_resources.Player).?.entity;
    const camera_state = app.getResource(resources.CameraState).?;
    const screen = app.getResource(core_resources.Screen).?;
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const pos = app.world.get(transform.PositionView, player).?;

    const w = @as(f32, @floatFromInt(screen.width));
    const h = @as(f32, @floatFromInt(screen.height));

    var x = xmath.lerp(pos.prev_x.*, pos.x.*, time.alpha);
    var y = xmath.lerp(pos.prev_y.*, pos.y.*, time.alpha);
    if (room_mgr.current) |room_id| {
        if (room_mgr.getBounds(room_id)) |bounds| {
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

const std = @import("std");
const math = std.math;

const engine = @import("engine");
const core = engine.core;
const xmath = engine.math;

const game = @import("game");
const resources = game.plugins.camera.resources;
const core_resources = game.plugins.core.resources;
const player_resources = game.plugins.player.resources;
const level_resources = game.plugins.level.resources;
const transform = game.components.transform;
