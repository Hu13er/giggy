
pub fn enemySpawnerSystem(app: *core.App) !void {
    const time_res = app.getResource(core.Time).?;

    // spawn an enemy every 100 tick
    if (time_res.tick % 100 != 0) return;

    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const render_targets = app.getResource(render_resources.RenderTargets).?;
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;

    const loco_animset = blk: {
        const val = assets_mgr.configValuePath(
            "animations",
            &.{ "locomotion", "skull" },
        ).?;
        break :blk try json.parseFromValue(components.animation.LocomotionAnimSet, app.gpa, val, .{});
    };
    defer loco_animset.deinit();

    const skull_animset = blk: {
        const val = assets_mgr.configValuePath(
            "animations",
            &.{ "skull" },
        ).?;
        break :blk try json.parseFromValue(components.animation.SkullAnimSet, app.gpa, val, .{});
    };
    defer skull_animset.deinit();

    const render_camera = blk: {
        const val = assets_mgr.configValuePath(
            "render_camera",
            &.{ "skull" },
        ).?;
        break :blk try json.parseFromValue(components.render.Model3DRenderCamera, app.gpa, val, .{});
    };
    defer render_camera.deinit();

    const rt = try render_targets.load(128, 128);
    const e = app.world.reserveEntity();
    try cb.spawn(e, .{
        components.enemy.Enemy{ .id = 1, .speed = 180.0, .state = .chase, .release_tick = 0 },
        components.transform.Position{ .x = 750, .y = 400, .prev_x = 200, .prev_y = 200 },
        components.transform.Velocity{ .x = 0, .y = 0 },
        components.collision.ColliderCircle{ .radius = 16.0, .mask = 1, .mass = 1.0 },
        components.transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 2 },
        components.animation.Animation{ .index = 0, .frame = 0, .accum = 0, .speed = 0, .priority = 0 },
        components.render.WidthHeight{ .w = 64, .h = 64 },
        components.render.Model3D{ .name = "skull", .render_texture = 0, .mesh = 0, .material = 1 },
        components.render.RenderInto{ .into = rt },
        loco_animset.value,
        skull_animset.value,
        render_camera.value,
        components.animation.LocomotionAnimState{ .moving = false },
        level_resources.roomFromName("level1"),
    });
}

const ENEMY_RELEASE_DELTA_TICK = 70;

pub fn enemyAISystem(app: *core.App) !void {
    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const time_res = app.getResource(core.Time).?;
    const chase_path_res = app.getResource(resource.ChasePath).?;
    const debug_res = app.getResource(debug.resources.DebugState).?;
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;
    const player_res = app.getResource(player_resources.Player) orelse return;

    const player_pos = app.world.get(components.transform.PositionView, player_res.entity) orelse return;
    const player_room = app.world.get(components.world.RoomView, player_res.entity) orelse return;
    const player_hurtbox = app.world.get(components.player.HurtBoxView, player_res.entity);

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
                    if (dist < 32.0) path.*.head += 1;

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

                if (player_hurtbox != null) {
                    if (it.getOrNull(components.collision.ColliderCircleView)) |enemy_col| blk: {
                        if (player_hurtbox.?.mask.* & enemy_col.mask.* == 0)
                            break :blk;
                        if (!rl.CheckCollisionCircles(
                            .{ .x = player_pos.x.*, .y = player_pos.y.* },
                            player_hurtbox.?.radius.* + 5.0,
                            .{ .x = pos.x.*, .y = pos.y.* },
                            enemy_col.radius.*,
                        )) break :blk;
                        enemy.state.* = .charge;
                        continue :state .charge;
                    }
                }
            },
            .charge => {
                vel.x.* = 0;
                vel.y.* = 0;
                if (enemy.release_tick.* == 0) {
                    enemy.release_tick.* = time_res.tick + ENEMY_RELEASE_DELTA_TICK;
                } else if (time_res.tick > enemy.release_tick.*) {
                    // release now!
                    enemy.state.* = .dead;
                    try spawnShockwave(app, &cb, .{ .x = pos.x.*, .y = pos.y.* });
                }
            },
            .dead => {
                // nothing to do for now
            },
        }
    }
}

pub const SKULL_ANIM_ATTACK_PRIORITY = 20;
pub const SKULL_ANIM_DEAD_PRIORITY = 100;

pub fn updateAnimationSystem(app: *core.App) !void {
    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const time_res = app.getResource(core.Time).?;
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;

    var it = app.world.query(&[_]type{
        components.enemy.Enemy,
        components.animation.Animation,
        components.animation.SkullAnimSet,
        components.render.WidthHeight,
        components.world.Room,
    });
    while (it.next()) |entity| {
        const enemy = it.get(components.enemy.EnemyView);
        const anim = it.get(components.animation.AnimationView);
        const set = it.get(components.animation.SkullAnimSetView);
        const wh = it.get(components.render.WidthHeightView);
        const room = it.get(components.world.RoomView);

        if (room_mgr.current != room.id.*) continue;

        switch (enemy.state.*) {
            .chase => {
                if (anim.priority.* > 0)
                    continue;
                anim.priority.* = 0;
            },
            .charge => {
                if (anim.priority.* > SKULL_ANIM_ATTACK_PRIORITY)
                    continue;
                anim.priority.* = SKULL_ANIM_ATTACK_PRIORITY;
                anim.index.* = set.attack.*;

                const model = assets_mgr.models.get("skull").?;
                const count = model.animations[anim.index.*].keyframeCount * set.attack_count.*;
                const window = time_res.fixed_dt * ENEMY_RELEASE_DELTA_TICK;
                anim.speed.* = @as(f32, @floatFromInt(count)) / window;

                // scale model
                const remaining = @as(f32, @floatFromInt(enemy.release_tick.* - time_res.tick));
                const progress = 1.0 - remaining / @as(f32, @floatFromInt(ENEMY_RELEASE_DELTA_TICK));
                const scaled = @min(64.0 + (94.0 - 64.0) * (progress * (1 + time_res.alpha * progress)), 94.0);
                wh.w.* = scaled;
                wh.h.* = scaled;
            },
            .dead => {
                if (anim.priority.* > SKULL_ANIM_DEAD_PRIORITY)
                    continue;
                anim.priority.* = SKULL_ANIM_DEAD_PRIORITY;
                if (anim.index.* != set.dead.*) {
                    anim.index.* = set.dead.*;
                    anim.speed.* = set.dead_speed.*;
                    anim.accum.* = 0;
                    anim.count.* = 0;
                }
                if (anim.count.* > 0) {
                    try cb.despawn(entity);
                }
            },
        }
    }
}

fn spawnShockwave(app: *core.App, cb: *ecs.CommandBuffer, pos: xmath.Vec2) !void {
    // TODO: we are reading external files whenever
    // spawning a shockwave. fix this!
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;
    const render_targets = app.getResource(render_resources.RenderTargets).?;

    // spawn a shockwave
    const shockwave_camera = blk: {
        const val = assets_mgr.configValuePath(
            "render_camera",
            &.{ "shockwave" },
        ).?;
        break :blk try json.parseFromValue(components.render.Model3DRenderCamera, app.gpa, val, .{});
    };
    defer shockwave_camera.deinit();

    const rt = try render_targets.load(512, 512);
    const e = app.world.reserveEntity();
    try cb.spawn(e, .{
        components.enemy.Shockwave{
            .damage = 256,
            .size_init = 32,
            .size_limit = 256,
            .ttl = 1.0,
        },
        components.enemy.ShockwaveHitbox{ .mask = 1 },
        components.render.Sprite{ .name = "shockwave", .index = 0 },
        components.render.WidthHeight{ .w = 0, .h = 0 },
        components.render.Alpha{ .alpha = 1.0 },
        components.render.ZIndex{ .value = -5 },
        components.render.RenderInto{ .into = rt },
        shockwave_camera.value,
        components.transform.Position{
            .x = pos.x,
            .y = pos.y,
            .prev_x = pos.x,
            .prev_y = pos.y,
        },
        components.animation.Animation{
            .index = 0,
            .speed = 250.0,
            .frame = 0,
            .accum = 0,
            .priority = 0,
        },
        // TODO: get it from players room
        level_resources.roomFromName("level1"),
    });
}

pub fn shockwaveExpandSystem(app: *core.App) !void {
    const time_res = app.getResource(core.Time).?;
    const hitmemo_res = app.getResource(resource.HitMemo).?;
    const render_targets = app.getResource(render_resources.RenderTargets).?;

    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    var it = app.world.query(&[_]type{
        components.enemy.Shockwave,
        components.render.WidthHeight,
        components.render.Alpha,
    });
    while (it.next()) |entity| {
        const shockwave = it.get(components.enemy.ShockwaveView);
        const wh = it.get(components.render.WidthHeightView);
        const alpha = it.get(components.render.AlphaView);

        if (shockwave.size.* < shockwave.size_limit.* - 1.0) {
            shockwave.accum.* += time_res.dt;
            shockwave.size.* = projectileScale(shockwave.accum.*, shockwave.size_init.*, shockwave.size_limit.*, 7.0);
            wh.w.* = shockwave.size.*;
            wh.h.* = shockwave.size.*;
        } else {
            shockwave.size.* = shockwave.size_limit.*;
            wh.w.* = shockwave.size.*;
            wh.h.* = shockwave.size.*;
            // fade out
            // TODO: we should despawn based on ticks not actual time
            const delta: f32 = time_res.dt / shockwave.ttl.*;
            if (alpha.alpha.* > 0) {
                alpha.alpha.* = @max(alpha.alpha.* - delta, 0);
            } else {
                alpha.alpha.* = 0;
                if (it.getOrNull(components.render.RenderIntoView)) |target| {
                    _ = render_targets.unload(target.into.*);
                }
                hitmemo_res.remove(entity);
                try cb.despawn(entity);
            }
        }
    }
}

const SHOCKWAVE_RENDER_ACTUAL_POR = 0.8;
const SHOCKWAVE_ESTIMATE_POINTS_COUNT = 16;

pub fn shockwaveHitboxSystem(app: *core.App) !void {
    const time_res = app.getResource(core.Time).?;
    const debug_res = app.getResource(debug.resources.DebugState);
    const hitmemo_res = app.getResource(resource.HitMemo).?;

    var it = app.world.query(&[_]type{
        components.transform.Position,
        components.enemy.Shockwave,
        components.enemy.ShockwaveHitbox,
        components.world.Room,
    });
    while (it.next()) |entity| {
        const pos = it.get(components.transform.PositionView);
        const shockwave = it.get(components.enemy.ShockwaveView);
        const hitbox = it.get(components.enemy.ShockwaveHitboxView);
        const rm = it.get(components.world.RoomView);

        if (hitbox.width.* < shockwave.size_limit.* * SHOCKWAVE_RENDER_ACTUAL_POR - 1.0) {
            hitbox.accum.* += 1;
            const t = @as(f32, @floatFromInt(hitbox.accum.*)) * (time_res.fixed_dt); // convert tick to actual time
            const size = projectileScale(t, shockwave.size_init.*, shockwave.size_limit.*, 7.0);
            hitbox.width.* = size * SHOCKWAVE_RENDER_ACTUAL_POR;
            hitbox.height.* = size * 0.6 * SHOCKWAVE_RENDER_ACTUAL_POR;
        }

        var samples: [SHOCKWAVE_ESTIMATE_POINTS_COUNT]rl.Vector2 = undefined;
        for (0..SHOCKWAVE_ESTIMATE_POINTS_COUNT) |t| {
            const teta = 2.0 * std.math.pi * @as(f32, @floatFromInt(t)) /
                            @as(f32, @floatFromInt(SHOCKWAVE_ESTIMATE_POINTS_COUNT));
            samples[t].x = pos.x.* + hitbox.width.* * std.math.cos(teta) / 2.0;
            samples[t].y = pos.y.* + hitbox.height.* * std.math.sin(teta) / 2.0;
        }

        if (debug_res != null) {
            debug_res.?.clearPoints();
            for (samples) |s|
                try debug_res.?.addPoint(.{ .x = s.x, .y = s.y, .color = rl.PINK });
        }

        hitbox.hit.* = false;
        var hurtbox_it = app.world.query(&[_]type{
            components.transform.Position,
            components.player.HurtBox,
            components.world.Room,
        });
        while (hurtbox_it.next()) |target| {
            const hb_pos = hurtbox_it.get(components.transform.PositionView);
            const hb_col = hurtbox_it.get(components.player.HurtBoxView);
            const hb_rm = hurtbox_it.get(components.world.RoomView);

            if (rm.id.* != hb_rm.id.*) continue;

            const nearest = xmath.nearestPointOnCircle(
                .{ .x = hb_pos.x.*, .y = hb_pos.y.* },
                hb_col.radius.*,
                .{ .x = pos.x.*, .y = pos.y.* },
            );
            if (!rl.CheckCollisionPointPoly(
                nearest.asRl(),
                @ptrCast(&samples),
                samples.len)) continue;
            if (try hitmemo_res.hit(entity, target)) {
                if (hurtbox_it.getOrNull(components.player.HealthView)) |health| {
                    health.value.* = @max(0, health.value.* - shockwave.damage.*);
                    std.log.debug("HIT! {} {}, HP: {}\n", .{entity, target, health.value.*});
                }
            }
        }
    }
}

fn projectileScale(t: f32, min_scale: f32, max_scale: f32, growth: f32) f32 {
    return max_scale - (max_scale - min_scale) * @exp(-growth * t);
}

const std = @import("std");
const json = std.json;

const engine = @import("engine");
const core = engine.core;
const ecs = engine.ecs;
const xmath = engine.math;
const rl = engine.raylib;
const path_finding = engine.algo.path_finding;

const game = @import("game");
const components = game.components;
const resource = game.plugins.enemy.resources;
const level_resources = game.plugins.level.resources;
const player_resources = game.plugins.player.resources;
const render_resources = game.plugins.render.resources;
const debug = game.plugins.debug;

