pub fn updateDebugModeSystem(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (rl.IsKeyReleased(rl.KEY_F9)) {
        debug.enabled = !debug.enabled;
    }
}

pub fn updateDebugValuesSystem(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (!debug.enabled) return;

    const time = app.getResource(core.Time).?;
    try debug.setFmt("time.dt", "{d:.4}", .{time.dt});
    try debug.setFmt("time.alpha", "{d:.2}", .{time.alpha});
    try debug.setFmt("world.entities", "{d}", .{app.world.count()});

    if (app.getResource(player_resources.Player)) |player_res| {
        if (app.world.get(transform.PositionView, player_res.entity)) |pos| {
            try debug.setFmt("player.pos", "{d:.1}, {d:.1}", .{ pos.x.*, pos.y.* });
        }
        if (app.world.get(transform.RotationView, player_res.entity)) |rot| {
            try debug.setFmt("player.rot", "{d:.1}, {d:.1}", .{ rot.target_teta.*, rot.teta.* });
        }
    }
}

pub fn renderDebugSystem(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (!debug.enabled) return;
    renderBoxes(app);
    renderColliders(app);
}

pub fn renderDebugOverlaySystem(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (!debug.enabled) return;
    const screen = app.getResource(core_resources.Screen).?;
    const fps_y: c_int = @intCast(screen.height);
    rl.DrawFPS(10, fps_y - 30);
    drawDebugValues(debug, 10, 10, 20, 16, rl.WHITE);
}

fn renderBoxes(app: *core.App) void {
    const time = app.getResource(core.Time).?;
    const assets = app.getResource(engine.assets.AssetManager).?;
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const current_room_id = room_mgr.current orelse return;
    var it_texture = app.world.query(&[_]type{ transform.Position, render_comps.Texture, world.Room });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(transform.PositionView);
        const texture_name = it_texture.getAuto(render_comps.Texture).name;
        const rm = it_texture.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const texture = assets.textures.getPtr(texture_name.*).?;
        const x = interpolatedPositionX(pos, time.alpha);
        const y = interpolatedPositionY(pos, time.alpha);
        rl.DrawRectangleLinesEx(rl.Rectangle{
            .x = x,
            .y = y,
            .width = @floatFromInt(texture.width),
            .height = @floatFromInt(texture.height),
        }, 4.0, rl.RED);
    }
    const render_targets = app.getResource(render_resources.RenderTargets).?;
    var it_render = app.world.query(&[_]type{ transform.Position, render_comps.RenderInto, world.Room });
    while (it_render.next()) |_| {
        const pos = it_render.get(transform.PositionView);
        const into = it_render.getAuto(render_comps.RenderInto).into;
        const rm = it_render.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

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
    const room_mgr = app.getResource(level_resources.RoomManager).?;
    const current_room_id = room_mgr.current orelse return;
    var it = app.world.query(&[_]type{ collision.ColliderLine, world.Room });
    while (it.next()) |_| {
        const line = it.get(collision.ColliderLineView);
        const rm = it.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const from: rl.Vector2 = .{ .x = line.x0.*, .y = line.y0.* };
        const to: rl.Vector2 = .{ .x = line.x1.*, .y = line.y1.* };
        rl.DrawLineEx(from, to, 4.0, rl.GREEN);
    }
    var circle_it = app.world.query(&[_]type{ transform.Position, collision.ColliderCircle, world.Room });
    while (circle_it.next()) |_| {
        const pos = circle_it.get(transform.PositionView);
        const col = circle_it.get(collision.ColliderCircleView);
        const rm = circle_it.get(world.RoomView);

        if (rm.id.* != current_room_id) continue;

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

fn drawDebugValues(debug: *resources.DebugState, x: c_int, y: c_int, line_height: c_int, font_size: c_int, color: rl.Color) void {
    var it = debug.values.iterator();
    var line_y = y;
    var buffer: [256]u8 = undefined;
    while (it.next()) |entry| {
        const line = std.fmt.bufPrintZ(&buffer, "{s}: {s}", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
        }) catch |err| switch (err) {
            error.NoSpaceLeft => std.fmt.bufPrintZ(&buffer, "{s}: <truncated>", .{
                entry.key_ptr.*,
            }) catch continue,
        };
        rl.DrawText(line, x, line_y, font_size, color);
        line_y += line_height;
    }
}

fn interpolatedPositionX(pos: transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_y.*, pos.y.*, alpha);
}

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
const std = @import("std");

const game = @import("game");
const resources = game.plugins.debug.resources;
const core_resources = game.plugins.core.resources;
const level_resources = game.plugins.level.resources;
const render_resources = game.plugins.render.resources;
const player_resources = game.plugins.player.resources;
const render = game.plugins.render;
const transform = game.components.transform;
const collision = game.components.collision;
const render_comps = game.components.render;
const world = game.components.world;
