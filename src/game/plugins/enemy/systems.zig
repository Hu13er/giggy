pub fn enemyAISystem(app: *core.App) !void {
    const time_res = app.getResource(core.Time).?;
    const chase_path_res = app.getResource(resource.ChasePath).?;
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
    while (it.next()) |entity| {
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

        state: switch (enemy.state.*) {
            .chase => {
                const path: *resource.ChasePath.Path = blk: {
                    if (chase_path_res.paths.getPtr(entity)) |path| {
                        if (time_res.tick - path.tick < 30)
                            break :blk path;
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

                    const path_opt = try pf.findPath(app.gpa, start_local, target_local);
                    defer if (path_opt) |path| app.gpa.free(path);

                    debug_res.clearPoints();
                    if (path_opt) |ps| {
                        for (ps) |p| try debug_res.addPoint(.{ .x = p.x, .y = p.y, .color = rl.BLUE });
                    }

                    break :blk try chase_path_res.update(entity, time_res.tick, path_opt);
                };

                const target: ?xmath.Vec2 = outer: {
                    if (path.points == null) break :outer null;

                    if (path.head >= path.points.?.len) break :outer null;
                    const head0 = path.points.?[path.head];
                    const dist = blk: {
                        const v = xmath.Vec2{
                            .x = pos.x.* - offset.x - head0.x,
                            .y = pos.y.* - offset.y - head0.y,
                        };
                        break :blk v.abs();
                    };
                    if (dist < 10.0) path.*.head += 1;

                    if (path.head >= path.points.?.len) break :outer null;
                    break :outer path.points.?[path.head];
                };
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

                const dist = blk: {
                    const v = xmath.Vec2{
                        .x = pos.x.* - player_pos.x.*,
                        .y = pos.y.* - player_pos.y.*,
                    };
                    break :blk v.abs();
                };
                if (dist < 64.0) {
                    enemy.state.* = .charge;
                    continue :state .charge;
                }
            },
            .charge => {
                vel.x.* = 0;
                vel.y.* = 0;
            },
            .dead => {},
        }
    }
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const xmath = engine.math;
const rl = engine.raylib;
const path_finding = engine.algo.path_finding;

const game = @import("game");
const components = game.components;
const resource = game.plugins.enemy.resources;
const level_resources = game.plugins.level.resources;
const player_resources = game.plugins.player.resources;
const debug = game.plugins.debug;

