pub fn updatePositionsSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    var it = app.world.query(&[_]type{ transform.Position, transform.Velocity });
    while (it.next()) |_| {
        const pos = it.get(transform.PositionView);
        const vel = it.get(transform.VelocityView);

        pos.prev_x.* = pos.x.*;
        pos.prev_y.* = pos.y.*;

        pos.x.* += time.dt * vel.x.*;
        pos.y.* += time.dt * vel.y.*;
    }
}

pub fn updateRotationsSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    var it = app.world.query(&[_]type{transform.Rotation});
    while (it.next()) |_| {
        const rot = it.get(transform.RotationView);

        rot.prev_teta.* = rot.teta.*;

        var delta = xmath.wrapAngleDeg(rot.target_teta.* - rot.teta.*);
        const max_step = rot.turn_speed_deg.* * time.dt;
        if (delta > max_step) delta = max_step;
        if (delta < -max_step) delta = -max_step;
        rot.teta.* += delta;
    }
}

pub fn colliderRigidBodySystem(app: *core.App) !void {
    try circleLineCollision(app);
}

fn circleLineCollision(app: *core.App) !void {
    var it = app.world.query(&[_]type{ transform.Position, collision.ColliderCircle, world_comp.Room });
    while (it.next()) |_| {
        const pos = it.get(transform.PositionView);
        const col = it.get(collision.ColliderCircleView);
        const room = it.get(world_comp.RoomView);

        if (col.mask.* == 0) continue;
        var pos_vec = xmath.Vec2{ .x = pos.x.*, .y = pos.y.* };
        pushFromEdges(&app.world, &pos_vec, col.radius.*, col.mask.*, room.id.*);
        pos.x.* = pos_vec.x;
        pos.y.* = pos_vec.y;
    }
}

fn pushFromEdges(world_ref: *ecs.World, pos: *xmath.Vec2, r: f32, mask: u64, room_id: u32) void {
    var it = world_ref.query(&[_]type{ collision.ColliderLine, world_comp.Room });
    while (it.next()) |_| {
        const line = it.get(collision.ColliderLineView);
        const room = it.get(world_comp.RoomView);
        if (room.id.* != room_id) continue;
        const a = xmath.Vec2{ .x = line.x0.*, .y = line.y0.* };
        const b = xmath.Vec2{ .x = line.x1.*, .y = line.y1.* };
        if ((line.mask.* & mask) == 0) continue;
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

const engine = @import("engine");
const core = engine.core;
const ecs = engine.ecs;
const xmath = engine.math;
const rl = engine.raylib;

const game = @import("game");
const transform = game.components.transform;
const collision = game.components.collision;
const world_comp = game.components.world;
