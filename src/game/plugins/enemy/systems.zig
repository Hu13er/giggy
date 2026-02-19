pub fn enemyChaseSystem(app: *core.App) !void {
    const debug_res = app.getResource(debug.resources.DebugState).?;
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;
    const player_res = app.getResource(player_resources.Player) orelse return;

    const player_pos = app.world.get(components.transform.PositionView, player_res.entity) orelse return;
    const player_room = app.world.get(components.world.RoomView, player_res.entity) orelse return;

    const bounds = room_mgr.getBounds(player_room.id.*) orelse return;
    const grid = room_mgr.getGrid(player_room.id.*) orelse return;

    var pf = path_finding.Pathfinder.initDefault(
        grid.w,
        grid.h,
        level_resources.RoomManager.cell_size,
        grid.walkables,
    );

    const offset = xmath.Vec2{ .x = bounds.x, .y = bounds.y };
    const target_local_raw = xmath.Vec2{
        .x = player_pos.x.* - offset.x,
        .y = player_pos.y.* - offset.y,
    };
    const target_local = pf.nearestWalkableWorld(target_local_raw, 1) orelse return;

    var it = app.world.query(&[_]type{
        components.enemy.Enemy,
        components.transform.Position,
        components.transform.Velocity,
        components.transform.Rotation,
        components.world.Room,
    });
    while (it.next()) |_| {
        const enemy = it.get(components.enemy.EnemyView);
        const pos = it.get(components.transform.PositionView);
        const vel = it.get(components.transform.VelocityView);
        const rot = it.get(components.transform.RotationView);
        const room = it.get(components.world.RoomView);

        if (room.id.* != player_room.id.*) {
            vel.x.* = 0;
            vel.y.* = 0;
            continue;
        }

        const start_local_raw = xmath.Vec2{
            .x = pos.x.* - offset.x,
            .y = pos.y.* - offset.y,
        };
        const start_local = pf.nearestWalkableWorld(start_local_raw, level_resources.RoomManager.cell_size / 2.0) orelse {
            vel.x.* = 0;
            vel.y.* = 0;
            continue;
        };

        debug_res.clearPoints();
        try debug_res.addPoint(.{ .x = start_local.x, .y = start_local.y });

        const path_opt = try pf.findPath(app.gpa, start_local, target_local);
        defer if (path_opt) |path| app.gpa.free(path);

        var target: ?xmath.Vec2 = null;
        if (path_opt) |path| {
            if (path.len >= 2) {
                const p = path[1];
                target = .{ .x = p.x + offset.x, .y = p.y + offset.y };
            }
        }

        if (target) |t| {
            var dir = xmath.Vec2{ .x = t.x - pos.x.*, .y = t.y - pos.y.* };
            dir = dir.normalize();
            vel.x.* = dir.x * enemy.speed.*;
            vel.y.* = dir.y * enemy.speed.*;
            const angle = std.math.atan2(vel.y.*, -vel.x.*);
            rot.target_teta.* = std.math.radiansToDegrees(angle) - 45.0;
        } else {
            vel.x.* = 0;
            vel.y.* = 0;
        }
    }
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const xmath = engine.math;

const game = @import("game");
const components = game.components;
const level_resources = game.plugins.level.resources;
const player_resources = game.plugins.player.resources;
const debug = game.plugins.debug;

const path_finding = engine.algo.path_finding;
