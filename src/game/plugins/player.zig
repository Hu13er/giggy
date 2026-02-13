pub const PlayerPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        const render_targets = app.getResource(resources.RenderTargets).?;
        _ = try render_targets.loadRenderTexture("player", 64, 64);

        const player = try app.world.spawn(.{
            comps.Position{ .x = 70, .y = 70, .prev_x = 70, .prev_y = 70 },
            comps.Velocity{ .x = 0, .y = 0 },
            comps.ColliderCircle{ .radius = 16.0 },
            comps.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 3 },
            comps.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
            comps.RenderInto{ .into = "player" },
            comps.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
            comps.MoveAnimation{ .idle = 0, .run = 2, .speed = 200.0 },
        });
        _ = try app.insertResource(resources.Player, .{ .entity = player });

        try app.addSystem(.update, playerInput);
        try app.addSystem(.fixed_update, updatePositions);
        try app.addSystem(.fixed_update, updateRotations);
        try app.addSystem(.fixed_update, playMovingsAnim);
        try app.addSystem(.update, cameraOnObject);
    }
};

fn playerInput(app: *core.App) !void {
    const world = &app.world;
    const player = app.getResource(resources.Player).?.entity;
    const vel = world.get(comps.VelocityView, player).?;
    const rot = world.get(comps.RotationView, player).?;
    var x: f32 = 0;
    var y: f32 = 0;

    if (rl.IsKeyDown(rl.KEY_D)) {
        x = 10;
    } else if (rl.IsKeyDown(rl.KEY_A)) {
        x = -10;
    }
    if (rl.IsKeyDown(rl.KEY_W)) {
        y = -10;
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        y = 10;
    }

    if (rl.IsGamepadAvailable(0)) {
        var gx = rl.GetGamepadAxisMovement(0, rl.GAMEPAD_AXIS_LEFT_X);
        var gy = rl.GetGamepadAxisMovement(0, rl.GAMEPAD_AXIS_LEFT_Y);
        const deadzone: f32 = 0.2;
        if (@abs(gx) < deadzone) gx = 0;
        if (@abs(gy) < deadzone) gy = 0;

        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_LEFT)) gx = -1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_RIGHT)) gx = 1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_UP)) gy = -1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_DOWN)) gy = 1;

        if (@abs(gx) > 0 or @abs(gy) > 0) {
            x = gx;
            y = gy;
        }
    }

    const l = std.math.sqrt(x * x + y * y);
    if (l > 0.1) {
        x = x / l * 250.0;
        y = y / l * 250.0;

        const angle = std.math.atan2(y, -x);
        rot.target_teta.* = std.math.radiansToDegrees(angle) - 45.0;
    }
    vel.x.* = x;
    vel.y.* = y;
}

fn updatePositions(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    var it = app.world.query(&[_]type{ comps.Position, comps.Velocity });
    while (it.next()) |_| {
        const pos = it.get(comps.PositionView);
        const vel = it.get(comps.VelocityView);

        pos.prev_x.* = pos.x.*;
        pos.prev_y.* = pos.y.*;

        var new_pos = xmath.Vec2{
            .x = pos.x.* + time.dt * vel.x.*,
            .y = pos.y.* + time.dt * vel.y.*,
        };

        if (it.getOrNull(comps.ColliderCircleView)) |collider| {
            pushFromEdges(&app.world, &new_pos, collider.radius.*);
        }

        pos.x.* = new_pos.x;
        pos.y.* = new_pos.y;
    }
}

fn updateRotations(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    var it = app.world.query(&[_]type{comps.Rotation});
    while (it.next()) |_| {
        const rot = it.get(comps.RotationView);

        rot.prev_teta.* = rot.teta.*;

        var delta = xmath.wrapAngleDeg(rot.target_teta.* - rot.teta.*);
        const max_step = rot.turn_speed_deg.* * time.dt;
        if (delta > max_step) delta = max_step;
        if (delta < -max_step) delta = -max_step;
        rot.teta.* += delta;
    }
}

fn playMovingsAnim(app: *core.App) !void {
    var it = app.world.query(&[_]type{ comps.Animation, comps.Velocity, comps.MoveAnimation });
    while (it.next()) |_| {
        const av = it.get(comps.AnimationView);
        const vv = it.get(comps.VelocityView);
        const mav = it.get(comps.MoveAnimationView);
        const new_anim = if (@abs(vv.x.*) > 0.1 or @abs(vv.y.*) > 0.1)
            mav.run.*
        else
            mav.idle.*;
        if (new_anim != av.index.*) {
            av.index.* = new_anim;
            av.frame.* = 0;
            av.speed.* = mav.speed.*;
        }
    }
}

fn cameraOnObject(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const player = app.getResource(resources.Player).?.entity;
    const camera_state = app.getResource(resources.CameraState).?;
    const screen = app.getResource(resources.Screen).?;
    const assets = app.getResource(engine.assets.AssetManager).?;

    const player_pos = app.world.get(comps.PositionView, player).?;

    const w = @as(f32, @floatFromInt(screen.width));
    const h = @as(f32, @floatFromInt(screen.height));

    const map = assets.textures.getPtr("map").?;

    var x = interpolatedPositionX(player_pos, time.alpha);
    const min_x = w / 2.0;
    const max_x = @as(f32, @floatFromInt(map.width)) - w / 2.0;
    x = @max(x, min_x);
    x = @min(x, max_x);

    var y = interpolatedPositionY(player_pos, time.alpha);
    const min_y = h / 2.0;
    const max_y = @as(f32, @floatFromInt(map.height)) - h / 2.0;
    y = @max(y, min_y);
    y = @min(y, max_y);

    camera_state.camera.target = .{ .x = x, .y = y };
}

fn pushFromEdges(world: *ecs.World, pos: *xmath.Vec2, r: f32) void {
    var it = world.query(&[_]type{comps.Line});
    while (it.next()) |_| {
        const line = it.get(comps.LineView);
        const a = xmath.Vec2{ .x = line.x0.*, .y = line.y0.* };
        const b = xmath.Vec2{ .x = line.x1.*, .y = line.y1.* };
        if (!rl.CheckCollisionCircleLine(
            pos.asRl(),
            r,
            a.asRl(),
            b.asRl(),
        )) continue;
        const dist = xmath.pushFromLine(pos.*, a, b, r);
        pos.* = pos.*.add(dist);
    }
}

fn interpolatedPositionX(pos: comps.PositionView, alpha: f32) f32 {
    return xmath.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: comps.PositionView, alpha: f32) f32 {
    return xmath.lerp(pos.prev_y.*, pos.y.*, alpha);
}

const std = @import("std");
const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const xmath = engine.math;
const ecs = engine.ecs;

const comps = @import("../components.zig");
const resources = @import("../resources.zig");
