
pub fn enemySpawnerSystem(app: *core.App) !void {
    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const render_targets = app.getResource(render_resources.RenderTargets).?;
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;

    const ghost_animset = blk: {
        const val = assets_mgr.configValuePath(
            "animations",
            &.{ "ghost" },
        ).?;
        break :blk try json.parseFromValue(components.animation.GhostAnimSet, app.gpa, val, .{});
    };
    defer ghost_animset.deinit();

    const render_camera = blk: {
        const val = assets_mgr.configValuePath(
            "render_camera",
            &.{ "ghost" },
        ).?;
        break :blk try json.parseFromValue(components.render.Model3DRenderCamera, app.gpa, val, .{});
    };
    defer render_camera.deinit();

    {
        const rt = try render_targets.load(128, 128);
        const e = app.world.reserveEntity();
        try cb.spawn(e, .{
            components.render.Alpha{ .alpha = GHOST_DEFAULT_ALPHA },
            components.enemy.Ghost{ .state = .hidden },
            components.transform.Position{ .x = 100, .y = 100, .prev_x = 100, .prev_y = 100 },
            components.transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 2 },
            components.render.Model3D{ .name = "ghost", .render_texture = 0, .mesh = 0, .material = 1 },
            components.animation.Animation{ .index = 0, .frame = 0, .accum = 0, .speed = 0, .priority = 0 },
            ghost_animset.value,
            render_camera.value,
            components.render.RenderInto{ .into = rt },
            level_resources.roomFromName("level1"),
        });
    }
    {
        for (0..3) |_| {
            const rt = try render_targets.load(128, 128);
            const e = app.world.reserveEntity();
            try cb.spawn(e, .{
                components.render.Alpha{ .alpha = GHOST_DEFAULT_ALPHA },
                components.enemy.Ghost{ .state = .hidden },
                components.transform.Position{ .x = 100, .y = 100, .prev_x = 100, .prev_y = 100 },
                components.transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 2 },
                components.render.Model3D{ .name = "ghost", .render_texture = 0, .mesh = 0, .material = 1 },
                components.animation.Animation{ .index = 0, .frame = 0, .accum = 0, .speed = 0, .priority = 0 },
                ghost_animset.value,
                render_camera.value,
                components.render.RenderInto{ .into = rt },
                level_resources.roomFromName("level2"),
            });

        }
    }
}

const GHOST_HIDDEN_STATE_TICK = 120;
const GHOST_APPEAR_STATE_TICK = 20;
const GHOST_CHARGE_STATE_TICK = 60;
const GHOST_DISAPPEAR_STATE_TICK = 20;

pub fn enemyAISystem(app: *core.App) !void {
    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const time_res = app.getResource(core.Time).?;
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;
    const player_res = app.getResource(player_resources.Player) orelse return;
    const player_pos = app.world.get(components.transform.PositionView, player_res.entity) orelse return;
    const player_room = app.world.get(components.world.RoomView, player_res.entity) orelse return;
    const bounds = room_mgr.getBounds(player_room.id.*) orelse return;
    const grid = room_mgr.getGrid(player_room.id.*) orelse return;

    var prng = std.Random.DefaultPrng.init(@intCast(time_res.tick));
    var pf = path_finding.Pathfinder.initDefault(
        grid.w,
        grid.h,
        level_resources.RoomManager.cell_size,
        grid.walkables,
    );

    var it = app.world.query(&[_]type{
        components.enemy.Ghost,
        components.transform.Position,
        components.transform.Rotation,
        components.world.Room,
    });
    while (it.next()) |_| {
        const enemy = it.get(components.enemy.GhostView);
        const pos = it.get(components.transform.PositionView);
        const rot = it.get(components.transform.RotationView);
        const room = it.get(components.world.RoomView);

        if (room.id.* != player_room.id.*) continue;

        state: switch (enemy.state.*) {
            .hidden => {
                if (enemy.next_cycle_tick.* == 0) {
                    enemy.next_cycle_tick.* = time_res.tick + GHOST_HIDDEN_STATE_TICK;
                }
                if (time_res.tick >= enemy.next_cycle_tick.*) {
                    enemy.next_cycle_tick.* = 0;
                    enemy.state.* = .appear;
                    continue :state .appear;
                }
            },
            .appear => {
                if (enemy.next_cycle_tick.* == 0) {
                    enemy.next_cycle_tick.* = time_res.tick + GHOST_APPEAR_STATE_TICK;
                    const rand = prng.random();

                    const offset = xmath.Vec2{ .x = bounds.x, .y = bounds.y };
                    const target = xmath.Vec2{
                        .x = player_pos.x.* - offset.x,
                        .y = player_pos.y.* - offset.y,
                    };

                    const new_x, const new_y = loop: for (1..32) |_| {
                        const teta = rand.float(f32) * 2 * std.math.pi;
                        const range = rand.float(f32) * 100 + 50;
                        const new_x = player_pos.x.* + range * std.math.cos(teta);
                        const new_y = player_pos.y.* + range * std.math.sin(teta);
                        if (try pf.findPath(app.gpa, .{ .x = new_x, .y = new_y }, target)) |p| {
                            app.gpa.free(p);
                            break :loop .{new_x, new_y};
                        }
                    } else .{ pos.x.*, pos.y.* };
                    pos.x.* = new_x;
                    pos.prev_x.* = new_x;
                    pos.y.* = new_y;
                    pos.prev_y.* = new_y;
                    const new_rot = blk: {
                        const dx = player_pos.x.* - pos.x.*;
                        const dy = player_pos.y.* - pos.y.*;
                        const angel = std.math.atan2(dx, dy);
                        break :blk angel * 180.0 / std.math.pi + 50.0;
                    };
                    rot.target_teta.* = new_rot;
                }
                if (time_res.tick > enemy.next_cycle_tick.*) {
                    enemy.next_cycle_tick.* = 0;
                    enemy.state.* = .charge;
                    continue :state .charge;
                }
            },
            .charge => {
                if (enemy.next_cycle_tick.* == 0) {
                    enemy.next_cycle_tick.* = time_res.tick + GHOST_CHARGE_STATE_TICK;
                }
                // aim while charging
                const new_rot = blk: {
                    const dx = player_pos.x.* - pos.x.*;
                    const dy = player_pos.y.* - pos.y.*;
                    const angel = std.math.atan2(dx, dy);
                    break :blk angel * 180.0 / std.math.pi + 50.0;
                };
                rot.target_teta.* = new_rot;
                if (time_res.tick > enemy.next_cycle_tick.*) {
                    enemy.next_cycle_tick.* = 0;
                    enemy.state.* = .disappear;
                    continue :state .disappear;
                }
            },
            .disappear => {
                if (enemy.next_cycle_tick.* == 0) {
                    enemy.next_cycle_tick.* = time_res.tick + GHOST_DISAPPEAR_STATE_TICK;
                }
                if (time_res.tick > enemy.next_cycle_tick.*) {
                    enemy.next_cycle_tick.* = 0;
                    enemy.state.* = .hidden;
                    continue :state .hidden;
                }
            },
        }
    }
}

pub const GHOST_DEFAULT_ALPHA = 0.9;
pub const GHOST_ANIM_ATTACK_PRIORITY = 20;
pub const GHOST_ANIM_DEAD_PRIORITY = 100;

pub fn updateAnimationSystem(app: *core.App) !void {
    var cb = try ecs.CommandBuffer.init(app.gpa);
    // TODO: here we ignored error!
    defer cb.flush(&app.world) catch unreachable;

    const time_res = app.getResource(core.Time).?;
    const debug_res = app.getResource(debug.resources.DebugState).?;
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;

    var it = app.world.query(&[_]type{
        components.enemy.Ghost,
        components.animation.Animation,
        components.animation.GhostAnimSet,
        components.render.Alpha,
        components.world.Room,
    });
    while (it.next()) |_| {
        const enemy = it.get(components.enemy.GhostView);
        const anim = it.get(components.animation.AnimationView);
        const set = it.get(components.animation.GhostAnimSetView);
        const alpha = it.get(components.render.AlphaView);
        const room = it.get(components.world.RoomView);

        if (room_mgr.current != room.id.*) continue;

        const p = if (enemy.next_cycle_tick.* >= time_res.tick)
            (@as(f32, @floatFromInt(enemy.next_cycle_tick.* - time_res.tick)) - time_res.alpha) /
                        @as(f32, @floatFromInt(GHOST_APPEAR_STATE_TICK))
        else
            0.0;
        switch (enemy.state.*) {
            .hidden => {
                alpha.alpha.* = 0.0;
            },
            .appear => {
                try debug_res.setFmt("next_cycle_tick", "{}", .{enemy.next_cycle_tick});
                try debug_res.setFmt("p", "{}", .{p});
                alpha.alpha.* = std.math.clamp((1.0 - p) * GHOST_DEFAULT_ALPHA, 0.0, GHOST_DEFAULT_ALPHA);
                anim.index.* = set.idle.*;
                anim.speed.* = set.idle_speed.*;
            },
            .charge => {
                alpha.alpha.* = GHOST_DEFAULT_ALPHA;
                anim.index.* = set.attack.*;
                const model = assets_mgr.models.get("ghost").?;
                const count = model.animations[anim.index.*].keyframeCount * 2;
                const window = time_res.fixed_dt * GHOST_CHARGE_STATE_TICK;
                anim.speed.* = @as(f32, @floatFromInt(count)) / window;
            },
            .disappear => {
                try debug_res.setFmt("next_cycle_tick", "{}", .{enemy.next_cycle_tick});
                try debug_res.setFmt("p", "{}", .{p});
                alpha.alpha.* = std.math.clamp(p * GHOST_DEFAULT_ALPHA, 0.0, GHOST_DEFAULT_ALPHA);
                anim.index.* = set.idle.*;
                anim.speed.* = set.idle_speed.*;
            },
        }
    }
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
