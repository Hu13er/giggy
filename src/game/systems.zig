pub fn playerInput(ctx: ecs.SystemCtx, player: ecs.Entity) void {
    const vel = ctx.world.get(comps.VelocityView, player).?;
    const rot = ctx.world.get(comps.RotationView, player).?;

    var x: f32 = 0;
    var y: f32 = 0;
    if (rl.IsKeyDown(rl.KEY_D)) {
        x = 10;
    } else if (rl.IsKeyDown(rl.KEY_A)) {
        x = -10;
    } else {
        x = 0;
    }
    if (rl.IsKeyDown(rl.KEY_W)) {
        y = -10;
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        y = 10;
    } else {
        y = 0;
    }
    const l = std.math.sqrt(x * x + y * y);
    if (l > 0.1) {
        x = x / l * 100.0;
        y = y / l * 100.0;

        const angle = std.math.atan2(y, -x);
        rot.teta.* = std.math.radiansToDegrees(angle) - 45.0;
    }
    vel.x.* = x;
    vel.y.* = y;
}

pub fn updatePositions(ctx: ecs.SystemCtx) void {
    var it = ctx.world.query(&[_]type{ comps.Position, comps.Velocity });
    while (it.next()) |_| {
        const pos = it.get(comps.PositionView);
        const vel = it.get(comps.VelocityView);

        const new_x = pos.x.* + ctx.dt * vel.x.*;
        const new_y = pos.y.* + ctx.dt * vel.y.*;

        if (checkEdgeCollision(ctx, new_x, new_y, 16.0)) continue;

        pos.x.* = new_x;
        pos.y.* = new_y;
    }
}

pub fn checkEdgeCollision(ctx: ecs.SystemCtx, x: f32, y: f32, r: f32) bool {
    var edge_it = ctx.world.query(&[_]type{comps.Line});
    while (edge_it.next()) |_| {
        const line = edge_it.get(comps.LineView);
        if (rl.CheckCollisionCircleLine(
            .{ .x = x, .y = y },
            r,
            .{ .x = line.x0.*, .y = line.y0.* },
            .{ .x = line.x1.*, .y = line.y1.* },
        )) {
            return true;
        }
    }
    return false;
}

pub fn animateMovingObjects(ctx: ecs.SystemCtx) void {
    var it = ctx.world.query(&[_]type{ comps.Animation, comps.Velocity, comps.MoveAnimation });
    while (it.next()) |_| {
        const av = it.get(comps.AnimationView);
        const vv = it.get(comps.VelocityView);
        const mav = it.get(comps.MoveAnimationView);
        if (@abs(vv.x.*) > 0.1 or @abs(vv.y.*) > 0.1) {
            av.index.* = mav.run.*;
        } else {
            av.index.* = mav.idle.*;
        }
    }
}

const std = @import("std");
const math = std.math;
const debug = std.debug;
const assert = debug.assert;

const rl = @import("../rl.zig").rl;
const ecs = @import("../ecs.zig");

const comps = @import("components.zig");
