pub fn playerInput(ctx: SystemCtx, player: ecs.Entity) void {
    const vel = ctx.world.get(comps.VelocityView, player).?;
    const rot = ctx.world.get(comps.RotationView, player).?;
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

pub fn updatePositions(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{ comps.Position, comps.Velocity });
    while (it.next()) |_| {
        const pos = it.get(comps.PositionView);
        const vel = it.get(comps.VelocityView);

        pos.prev_x.* = pos.x.*;
        pos.prev_y.* = pos.y.*;

        var new_pos = xmath.Vec2{
            .x = pos.x.* + ctx.dt * vel.x.*,
            .y = pos.y.* + ctx.dt * vel.y.*,
        };

        if (it.getOrNull(comps.ColliderCircleView)) |collider| {
            pushFromEdges(ctx, &new_pos, collider.radius.*);
        }

        pos.x.* = new_pos.x;
        pos.y.* = new_pos.y;
    }
}

pub fn updateRotations(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{comps.Rotation});
    while (it.next()) |_| {
        const rot = it.get(comps.RotationView);

        rot.prev_teta.* = rot.teta.*;

        var delta = wrapAngleDeg(rot.target_teta.* - rot.teta.*);
        const max_step = rot.turn_speed_deg.* * ctx.dt;
        if (delta > max_step) delta = max_step;
        if (delta < -max_step) delta = -max_step;
        rot.teta.* += delta;
    }
}

pub fn pushFromEdges(ctx: SystemCtx, pos: *xmath.Vec2, r: f32) void {
    var it = ctx.world.query(&[_]type{comps.Line});
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

pub fn checkEdgeCollision(ctx: SystemCtx, x: f32, y: f32, r: f32) bool {
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

pub fn playMovingsAnim(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{ comps.Animation, comps.Velocity, comps.MoveAnimation });
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

pub fn cameraOnObject(ctx: SystemCtx, camera: *rl.Camera2D, object: ecs.Entity) void {
    const player_pos = ctx.world.get(comps.PositionView, object).?;

    const w = @as(f32, @floatFromInt(Rescources.screenWidth));
    const h = @as(f32, @floatFromInt(Rescources.screenHeight));

    const map = ctx.resc.textures.getPtr("map").?;

    var x = interpolatedPositionX(player_pos, ctx.alpha);
    const min_x = w / 2.0;
    const max_x = @as(f32, @floatFromInt(map.width)) - w / 2.0;
    x = @max(x, min_x);
    x = @min(x, max_x);

    var y = interpolatedPositionY(player_pos, ctx.alpha);
    const min_y = h / (2.0);
    const max_y = @as(f32, @floatFromInt(map.height)) - h / 2.0;
    y = @max(y, min_y);
    y = @min(y, max_y);

    camera.*.target = .{ .x = x, .y = y };
}

pub fn upldate3dModelAnimations(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{ comps.Model3D, comps.Animation });
    while (it.next()) |_| {
        const mv = it.get(comps.Model3DView);
        const am = it.get(comps.AnimationView);

        const model = ctx.resc.models.getPtr(mv.name.*).?;
        const frame_count = @as(usize, @intCast(model.animations[am.index.*].frameCount));
        const max_acc = @as(f32, @floatFromInt(frame_count)) / am.speed.*;

        am.acc.* += ctx.dt;
        while (am.acc.* > max_acc) : (am.acc.* -= max_acc) {}
        const new_current = @as(usize, @intFromFloat(am.acc.* * am.speed.*)) % frame_count;
        am.frame.* = new_current;

        rl.UpdateModelAnimationBones(
            model.model,
            model.animations[am.index.*],
            @intCast(new_current),
        );
    }
}

pub fn render3dModels(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{
        comps.Model3D,
        comps.Rotation,
        comps.RenderInto,
    });
    while (it.next()) |_| {
        const mv = it.get(comps.Model3DView);
        const rv = it.get(comps.RotationView);
        const into = it.getAuto(comps.RenderInto).into;

        const rotation = interpolatedRotation(rv, ctx.alpha);

        const model = ctx.resc.models.getPtr(mv.name.*).?;
        const render_texture = ctx.resc.render_textures.get(into.*).?;

        rl.BeginTextureMode(render_texture);
        rl.ClearBackground(rl.BLANK);
        rl.BeginMode3D(camera3d);
        rl.DrawModelEx(
            model.model,
            rl.Vector3{ .x = 0, .y = 0, .z = 0 },
            rl.Vector3{ .x = 0, .y = 1, .z = 0 }, // rotate around Y
            rotation,
            rl.Vector3{ .x = 1, .y = 1, .z = 1 },
            rl.WHITE,
        );
        // rl.DrawGrid(10, 1.0);
        rl.EndMode3D();
        rl.EndTextureMode();
    }
}

pub fn renderBackground(ctx: SystemCtx, name: []const u8) void {
    const background = ctx.resc.textures.get(name).?;
    rl.DrawTexture(background, 0, 0, rl.WHITE);
}

pub fn collectRenderables(ctx: SystemCtx, gpa: mem.Allocator, list: *RenderableList) !void {
    var it_texture = ctx.world.query(&[_]type{ comps.Position, comps.WidthHeight, comps.Texture });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(comps.PositionView);
        const wh = it_texture.get(comps.WidthHeightView);
        const t = it_texture.get(comps.TextureView);

        const texture = ctx.resc.textures.getPtr(t.name.*).?;

        try list.append(gpa, Renderable{
            .x = interpolatedPositionX(pos, ctx.alpha),
            .y = interpolatedPositionY(pos, ctx.alpha),
            .w = wh.w.*,
            .h = wh.h.*,
            .flip_h = false,
            .texture = texture.*,
        });
    }
    var it_render = ctx.world.query(&[_]type{ comps.Position, comps.RenderInto });
    while (it_render.next()) |_| {
        const pos = it_render.get(comps.PositionView);
        const into = it_render.getAuto(comps.RenderInto).into;
        const render_texture = ctx.resc.render_textures.get(into.*).?;

        const w = @as(f32, @floatFromInt(render_texture.texture.width));
        const h = @as(f32, @floatFromInt(render_texture.texture.height));

        try list.append(gpa, Renderable{
            .x = interpolatedPositionX(pos, ctx.alpha) - h / 2.0,
            .y = interpolatedPositionY(pos, ctx.alpha) - w / 2.0,
            .w = w,
            .h = h,
            .flip_h = true,
            .texture = render_texture.texture,
        });
    }
}

pub fn renderRenderables(_: SystemCtx, list: *RenderableList) void {
    std.sort.insertion(Renderable, list.items, {}, struct {
        fn lessThan(_: void, a: Renderable, b: Renderable) bool {
            if (a.y + a.h < b.y + b.h) return true;
            return false;
        }
    }.lessThan);
    for (list.items) |r| {
        const flip: f32 = if (r.flip_h) -1 else 1;
        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = r.w,
            .height = r.h * flip,
        };
        rl.DrawTextureRec(r.texture, src, .{ .x = r.x, .y = r.y }, rl.WHITE);
    }
}

pub fn updateDebugMode(ctx: SystemCtx) bool {
    if (rl.IsKeyReleased(rl.KEY_F9)) {
        ctx.resc.debug = !ctx.resc.debug;
    }
    return ctx.resc.debug;
}

pub fn renderBoxes(ctx: SystemCtx) void {
    var it_texture = ctx.world.query(&[_]type{ comps.Position, comps.Texture });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(comps.PositionView);
        const texture_name = it_texture.getAuto(comps.Texture).name;
        const texture = ctx.resc.textures.get(texture_name.*).?;
        const x = interpolatedPositionX(pos, ctx.alpha);
        const y = interpolatedPositionY(pos, ctx.alpha);
        rl.DrawRectangleLinesEx(rl.Rectangle{
            .x = x,
            .y = y,
            .width = @floatFromInt(texture.width),
            .height = @floatFromInt(texture.height),
        }, 4.0, rl.RED);
    }
    var it_render = ctx.world.query(&[_]type{ comps.Position, comps.RenderInto });
    while (it_render.next()) |_| {
        const pos = it_render.get(comps.PositionView);
        const into = it_render.getAuto(comps.RenderInto).into;
        const render_texture = ctx.resc.render_textures.get(into.*).?;
        const w: f32 = @floatFromInt(render_texture.texture.width);
        const h: f32 = @floatFromInt(render_texture.texture.height);
        const x = interpolatedPositionX(pos, ctx.alpha);
        const y = interpolatedPositionY(pos, ctx.alpha);
        rl.DrawRectangleLinesEx(rl.Rectangle{
            .x = x - w / 2.0,
            .y = y - h / 2.0,
            .width = w,
            .height = h,
        }, 4.0, rl.RED);
    }
}

pub fn renderColliders(ctx: SystemCtx) void {
    var it = ctx.world.query(&[_]type{comps.Line});
    while (it.next()) |_| {
        const line = it.get(comps.LineView);
        const from: rl.Vector2 = .{ .x = line.x0.*, .y = line.y0.* };
        const to: rl.Vector2 = .{ .x = line.x1.*, .y = line.y1.* };
        rl.DrawLineEx(from, to, 4.0, rl.GREEN);
    }
    var circle_it = ctx.world.query(&[_]type{ comps.Position, comps.ColliderCircle });
    while (circle_it.next()) |_| {
        const pos = circle_it.get(comps.PositionView);
        const col = circle_it.get(comps.ColliderCircleView);
        const x = interpolatedPositionX(pos, ctx.alpha);
        const y = interpolatedPositionY(pos, ctx.alpha);
        rl.DrawRing(
            .{ .x = x, .y = y },
            col.radius.*,
            col.radius.* + 4.0,
            0,
            360,
            0,
            rl.YELLOW,
        );
    }
}

pub const Renderable = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    texture: rl.Texture,
    flip_h: bool,
};

pub const RenderableList = std.ArrayList(Renderable);

const camera3d = rl.Camera3D{
    .position = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
    .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .fovy = 3.0,
    .projection = rl.CAMERA_ORTHOGRAPHIC,
};

fn interpolatedPositionX(pos: comps.PositionView, alpha: f32) f32 {
    return lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: comps.PositionView, alpha: f32) f32 {
    return lerp(pos.prev_y.*, pos.y.*, alpha);
}

fn interpolatedRotation(rot: comps.RotationView, alpha: f32) f32 {
    return lerpAngleDeg(rot.prev_teta.*, rot.teta.*, alpha);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn wrapAngleDeg(angle: f32) f32 {
    var a = angle;
    while (a > 180.0) a -= 360.0;
    while (a < -180.0) a += 360.0;
    return a;
}

fn lerpAngleDeg(a: f32, b: f32, t: f32) f32 {
    return a + wrapAngleDeg(b - a) * t;
}

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const rl = engine.rl;
const ecs = engine.ecs;
const xmath = engine.math;

const comps = @import("components.zig");
const Rescources = @import("resources.zig");
const SystemCtx = @import("main.zig").SystemCtx;
