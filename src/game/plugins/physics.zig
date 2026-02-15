pub const PhysicsPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        try app.addSystem(.fixed_update, UpdatePositionsSystem);
        try app.addSystem(.fixed_update, UpdateRotationsSystem);
        try app.addSystem(.fixed_update, ColliderRigidBodySystem);
    }
};

const UpdatePositionsSystem = struct {
    pub const provides: []const []const u8 = &.{ "movement", "physics" };
    pub const after_all_labels: []const []const u8 = &.{"input"};

    pub fn run(app: *core.App) !void {
        const time = app.getResource(core.Time).?;
        var it = app.world.query(&[_]type{ comps.Position, comps.Velocity });
        while (it.next()) |_| {
            const pos = it.get(comps.PositionView);
            const vel = it.get(comps.VelocityView);

            pos.prev_x.* = pos.x.*;
            pos.prev_y.* = pos.y.*;

            pos.x.* += time.dt * vel.x.*;
            pos.y.* += time.dt * vel.y.*;
        }
    }
};

const UpdateRotationsSystem = struct {
    pub const provides: []const []const u8 = &.{ "movement", "physics" };
    pub const after_all_labels: []const []const u8 = &.{"input"};

    pub fn run(app: *core.App) !void {
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
};

const ColliderRigidBodySystem = struct {
    pub const provides: []const []const u8 = &.{ "collision", "physics" };
    pub const after_all_labels: []const []const u8 = &.{"movement"};

    pub fn run(app: *core.App) !void {
        try circleLineCollision(app);
    }

    fn circleLineCollision(app: *core.App) !void {
        var it = app.world.query(&[_]type{ comps.Position, comps.ColliderCircle, comps.Room });
        while (it.next()) |_| {
            const pos = it.get(comps.PositionView);
            const col = it.get(comps.ColliderCircleView);
            const room = it.get(comps.RoomView);

            var pos_vec = xmath.Vec2{ .x = pos.x.*, .y = pos.y.* };
            pushFromEdges(&app.world, &pos_vec, col.radius.*, col.mask.*, room.id.*);
            pos.x.* = pos_vec.x;
            pos.y.* = pos_vec.y;
        }
    }

    fn pushFromEdges(world: *ecs.World, pos: *xmath.Vec2, r: f32, mask: u64, room_id: u32) void {
        var it = world.query(&[_]type{ comps.ColliderLine, comps.Room });
        while (it.next()) |_| {
            const line = it.get(comps.ColliderLineView);
            const room = it.get(comps.RoomView);
            if (room.id.* != room_id) continue;
            const a = xmath.Vec2{ .x = line.x0.*, .y = line.y0.* };
            const b = xmath.Vec2{ .x = line.x1.*, .y = line.y1.* };
            if (line.mask.* & mask == 0) continue;
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
};

const std = @import("std");
const engine = @import("engine");
const core = engine.core;
const ecs = engine.ecs;
const xmath = engine.math;
const rl = engine.rl;

const comps = @import("../components.zig");
