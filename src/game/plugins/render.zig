pub const RenderPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        try app.addSystem(.update, update3dModelAnimations);
        try app.addSystem(.render, render3dModels);
        try app.addSystem(.render, renderBegin);
        try app.addSystem(.render, renderBackground);
        try app.addSystem(.render, collectRenderables);
        try app.addSystem(.render, renderRenderables);
        try app.addSystem(.render, renderDebug);
        try app.addSystem(.render, renderEnd);
        try app.addSystem(.render, clearRenderables);
    }
};

fn update3dModelAnimations(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    var it = app.world.query(&[_]type{ comps.Model3D, comps.Animation });
    while (it.next()) |_| {
        const mv = it.get(comps.Model3DView);
        const am = it.get(comps.AnimationView);

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

fn render3dModels(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    const render_targets = app.getResource(resources.RenderTargets).?;
    var it = app.world.query(&[_]type{
        comps.Model3D,
        comps.Rotation,
        comps.RenderInto,
    });
    while (it.next()) |_| {
        const mv = it.get(comps.Model3DView);
        const rv = it.get(comps.RotationView);
        const into = it.getAuto(comps.RenderInto).into;

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

fn renderBegin(app: *core.App) !void {
    const camera_state = app.getResource(resources.CameraState).?;
    rl.BeginDrawing();
    rl.ClearBackground(rl.GRAY);
    rl.BeginMode2D(camera_state.camera);
}

fn renderBackground(app: *core.App) !void {
    const assets = app.getResource(engine.assets.AssetManager).?;
    const background = assets.textures.get("map").?;
    rl.DrawTexture(background, 0, 0, rl.WHITE);
}

fn collectRenderables(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    const render_targets = app.getResource(resources.RenderTargets).?;
    const renderables_list = app.getResource(resources.Renderables).?;
    const list = &renderables_list.list;

    var it_texture = app.world.query(&[_]type{ comps.Position, comps.WidthHeight, comps.Texture });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(comps.PositionView);
        const wh = it_texture.get(comps.WidthHeightView);
        const t = it_texture.get(comps.TextureView);

        const texture = assets.textures.getPtr(t.name.*).?;

        try list.append(renderables_list.gpa, renderables.Renderable{
            .x = interpolatedPositionX(pos, time.alpha),
            .y = interpolatedPositionY(pos, time.alpha),
            .w = wh.w.*,
            .h = wh.h.*,
            .flip_h = false,
            .texture = texture.*,
        });
    }
    var it_render = app.world.query(&[_]type{ comps.Position, comps.RenderInto });
    while (it_render.next()) |_| {
        const pos = it_render.get(comps.PositionView);
        const into = it_render.getAuto(comps.RenderInto).into;
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
        });
    }
}

fn renderRenderables(app: *core.App) !void {
    const renderables_list = app.getResource(resources.Renderables).?;
    const list = &renderables_list.list;
    std.sort.insertion(renderables.Renderable, list.items, {}, struct {
        fn lessThan(_: void, a: renderables.Renderable, b: renderables.Renderable) bool {
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

fn renderDebug(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (!debug.enabled) return;
    renderBoxes(app);
    renderColliders(app);
}

fn renderEnd(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    const screen = app.getResource(resources.Screen).?;
    rl.EndMode2D();
    if (debug.enabled) {
        const fps_y: c_int = @intCast(screen.height);
        rl.DrawFPS(10, fps_y - 30);
    }
    rl.EndDrawing();
}

fn clearRenderables(app: *core.App) !void {
    const renderables_list = app.getResource(resources.Renderables).?;
    renderables_list.list.clearRetainingCapacity();
}

fn renderBoxes(app: *core.App) void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    var it_texture = app.world.query(&[_]type{ comps.Position, comps.Texture });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(comps.PositionView);
        const texture_name = it_texture.getAuto(comps.Texture).name;
        const texture = assets.textures.get(texture_name.*).?;
        const x = interpolatedPositionX(pos, time.alpha);
        const y = interpolatedPositionY(pos, time.alpha);
        rl.DrawRectangleLinesEx(rl.Rectangle{
            .x = x,
            .y = y,
            .width = @floatFromInt(texture.width),
            .height = @floatFromInt(texture.height),
        }, 4.0, rl.RED);
    }
    const render_targets = app.getResource(resources.RenderTargets).?;
    var it_render = app.world.query(&[_]type{ comps.Position, comps.RenderInto });
    while (it_render.next()) |_| {
        const pos = it_render.get(comps.PositionView);
        const into = it_render.getAuto(comps.RenderInto).into;
        const render_texture = render_targets.render_textures.get(into.*).?;
        const w: f32 = @floatFromInt(render_texture.texture.width);
        const h: f32 = @floatFromInt(render_texture.texture.height);
        const x = interpolatedPositionX(pos, time.alpha);
        const y = interpolatedPositionY(pos, time.alpha);
        rl.DrawRectangleLinesEx(rl.Rectangle{
            .x = x - w / 2.0,
            .y = y - h / 2.0,
            .width = w,
            .height = h,
        }, 4.0, rl.RED);
    }
}

fn renderColliders(app: *core.App) void {
    const time = app.getResource(core.Time).?;
    var it = app.world.query(&[_]type{comps.Line});
    while (it.next()) |_| {
        const line = it.get(comps.LineView);
        const from: rl.Vector2 = .{ .x = line.x0.*, .y = line.y0.* };
        const to: rl.Vector2 = .{ .x = line.x1.*, .y = line.y1.* };
        rl.DrawLineEx(from, to, 4.0, rl.GREEN);
    }
    var circle_it = app.world.query(&[_]type{ comps.Position, comps.ColliderCircle });
    while (circle_it.next()) |_| {
        const pos = circle_it.get(comps.PositionView);
        const col = circle_it.get(comps.ColliderCircleView);
        const x = interpolatedPositionX(pos, time.alpha);
        const y = interpolatedPositionY(pos, time.alpha);
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

const camera3d = rl.Camera3D{
    .position = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
    .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    .fovy = 3.0,
    .projection = rl.CAMERA_ORTHOGRAPHIC,
};

fn interpolatedPositionX(pos: comps.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: comps.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_y.*, pos.y.*, alpha);
}

fn interpolatedRotation(rot: comps.RotationView, alpha: f32) f32 {
    return engine.math.lerpAngleDeg(rot.prev_teta.*, rot.teta.*, alpha);
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const ecs = engine.ecs;

const comps = @import("../components.zig");
const resources = @import("../resources.zig");
const renderables = @import("render/renderables.zig");
