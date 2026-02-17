pub fn updateLocomotionAnimationSystem(app: *core.App) !void {
    const assets = app.getResource(engine.assets.AssetManager).?;
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const current_room_id = room_mgr.current orelse return;

    var it = app.world.query(&[_]type{
        animation.Animation,
        transform.Velocity,
        animation.LocomotionAnimSet,
        animation.LocomotionAnimState,
        render.Model3D,
        world.Room,
    });
    while (it.next()) |_| {
        const av = it.get(animation.AnimationView);
        const vv = it.get(transform.VelocityView);
        const set = it.get(animation.LocomotionAnimSetView);
        const state = it.get(animation.LocomotionAnimStateView);
        const mv = it.get(render.Model3DView);
        const rm = it.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const speed = std.math.sqrt(vv.x.* * vv.x.* + vv.y.* * vv.y.*);
        const start = set.move_start.*;
        const stop = set.move_stop.*;
        if (!state.moving.* and speed >= start) state.moving.* = true;
        if (state.moving.* and speed <= stop) state.moving.* = false;

        const new_anim = if (state.moving.*) set.run.* else set.idle.*;
        if (new_anim != av.index.*) {
            const model = assets.models.getPtr(mv.name.*).?;
            const old_frames = @as(f32, @floatFromInt(model.animations[av.index.*].frameCount));
            const prev_speed = @max(av.speed.*, 0.001);
            const old_max_acc = old_frames / prev_speed;
            const phase = if (old_max_acc > 0) av.acc.* / old_max_acc else 0;

            av.index.* = new_anim;

            const new_frames_count = @as(usize, @intCast(model.animations[av.index.*].frameCount));
            const base_speed = set.base_speed.*;
            const ref = @max(set.run_speed_ref.*, 0.001);
            const scale = std.math.clamp(speed / ref, set.speed_scale_min.*, set.speed_scale_max.*);
            av.speed.* = base_speed * scale;
            const new_max_acc = @as(f32, @floatFromInt(new_frames_count)) / av.speed.*;
            av.acc.* = phase * new_max_acc;
            av.frame.* = @as(usize, @intFromFloat(av.acc.* * av.speed.*)) % new_frames_count;
        } else if (state.moving.*) {
            const base_speed = set.base_speed.*;
            const ref = @max(set.run_speed_ref.*, 0.001);
            const scale = std.math.clamp(speed / ref, set.speed_scale_min.*, set.speed_scale_max.*);
            av.speed.* = base_speed * scale;
        } else {
            av.speed.* = set.base_speed.*;
        }
    }
}

pub fn update3DModelAnimationsSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    var it = app.world.query(&[_]type{ render.Model3D, animation.Animation });
    while (it.next()) |_| {
        const mv = it.get(render.Model3DView);
        const am = it.get(animation.AnimationView);

        const model = assets.models.getPtr(mv.name.*).?;
        const frame_count = @as(usize, @intCast(model.animations[am.index.*].frameCount));
        const max_acc = @as(f32, @floatFromInt(frame_count)) / am.speed.*;

        am.acc.* += time.dt;
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

pub fn render3DModelsSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    const render_targets = app.getResource(resources.RenderTargets).?;
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const current_room_id = room_mgr.current orelse return;
    var it = app.world.query(&[_]type{
        render.Model3D,
        transform.Rotation,
        render.RenderInto,
        world.Room,
    });
    while (it.next()) |_| {
        const mv = it.get(render.Model3DView);
        const rv = it.get(transform.RotationView);
        const into = it.getAuto(render.RenderInto).into;
        const rm = it.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const rotation = interpolatedRotation(rv, time.alpha);

        const model = assets.models.getPtr(mv.name.*).?;
        const render_texture = render_targets.render_textures.get(into.*).?;

        rl.BeginTextureMode(render_texture);
        rl.ClearBackground(rl.BLANK);
        rl.BeginMode3D(camera3d);
        rl.DrawModelEx(
            model.model,
            rl.Vector3{ .x = 0, .y = 0, .z = 0 },
            rl.Vector3{ .x = 0, .y = 1, .z = 0 },
            rotation,
            rl.Vector3{ .x = 1, .y = 1, .z = 1 },
            rl.WHITE,
        );
        rl.EndMode3D();
        rl.EndTextureMode();
    }
}

pub fn renderBeginSystem(app: *core.App) !void {
    const camera_state = app.getResource(camera_resources.CameraState).?;
    rl.BeginDrawing();
    rl.ClearBackground(rl.GRAY);
    rl.BeginMode2D(camera_state.camera);
}

pub fn collectRenderablesSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    const render_targets = app.getResource(resources.RenderTargets).?;
    const renderables_list = app.getResource(resources.Renderables).?;
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const current_room_id = room_mgr.current orelse return;
    const list = &renderables_list.list;

    var it_texture = app.world.query(&[_]type{ transform.Position, render.WidthHeight, render.Texture, world.Room });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(transform.PositionView);
        const wh = it_texture.get(render.WidthHeightView);
        const t = it_texture.get(render.TextureView);
        const rm = it_texture.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const texture = assets.textures.getPtr(t.name.*).?;

        try list.append(renderables_list.gpa, renderables.Renderable{
            .x = interpolatedPositionX(pos, time.alpha),
            .y = interpolatedPositionY(pos, time.alpha),
            .w = wh.w.*,
            .h = wh.h.*,
            .flip_h = false,
            .texture = texture.*,
            .z_index = t.z_index.*,
        });
    }
    var it_render = app.world.query(&[_]type{ transform.Position, render.RenderInto, world.Room });
    while (it_render.next()) |_| {
        const pos = it_render.get(transform.PositionView);
        const into = it_render.getAuto(render.RenderInto).into;
        const rm = it_render.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;
        const render_texture = render_targets.render_textures.get(into.*).?;

        const w = @as(f32, @floatFromInt(render_texture.texture.width));
        const h = @as(f32, @floatFromInt(render_texture.texture.height));

        try list.append(renderables_list.gpa, renderables.Renderable{
            .x = interpolatedPositionX(pos, time.alpha) - h / 2.0,
            .y = interpolatedPositionY(pos, time.alpha) - w / 2.0,
            .w = w,
            .h = h,
            .flip_h = true,
            .texture = render_texture.texture,
            .z_index = 0,
        });
    }
}

pub fn renderRenderablesSystem(app: *core.App) !void {
    const renderables_list = app.getResource(resources.Renderables).?;
    const list = &renderables_list.list;
    std.sort.insertion(renderables.Renderable, list.items, {}, struct {
        fn lessThan(_: void, a: renderables.Renderable, b: renderables.Renderable) bool {
            if (a.z_index != b.z_index) return a.z_index < b.z_index;
            return a.y + a.h < b.y + b.h;
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

pub fn renderEndMode2DSystem(app: *core.App) !void {
    _ = app;
    rl.EndMode2D();
}

pub fn renderEndSystem(app: *core.App) !void {
    _ = app;
    rl.EndDrawing();
}

pub fn clearRenderablesSystem(app: *core.App) !void {
    const renderables_list = app.getResource(resources.Renderables).?;
    renderables_list.list.clearRetainingCapacity();
}

const camera3d = rl.Camera3D{
    .position = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
    .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .fovy = 3.0,
    .projection = rl.CAMERA_ORTHOGRAPHIC,
};

fn interpolatedPositionX(pos: transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_y.*, pos.y.*, alpha);
}

fn interpolatedRotation(rot: transform.RotationView, alpha: f32) f32 {
    return engine.math.lerpAngleDeg(rot.prev_teta.*, rot.teta.*, alpha);
}

pub const LabelRenderPrepass = "render.prepass";
pub const LabelRenderBegin = "render.begin";
pub const LabelRenderPass = "render.pass";
pub const LabelRenderEndMode2D = "render.end_mode_2d";
pub const LabelRenderOverlay = "render.overlay";
pub const LabelRenderEnd = "render.end";

pub const CollectRenderablesSystemId = "render.collect";
pub const RenderRenderablesSystemId = "render.renderables";

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const game = @import("game");
const animation = game.components.animation;
const transform = game.components.transform;
const render = game.components.render;
const world = game.components.world;
const resources = game.plugins.render.resources;
const camera_resources = game.plugins.camera.resources;
const level_resources = game.plugins.level.resources;
const renderables = @import("renderables.zig");
