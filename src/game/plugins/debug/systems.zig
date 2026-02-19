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
        if (app.world.get(components.transform.PositionView, player_res.entity)) |pos| {
            try debug.setFmt("player.pos", "{d:.1}, {d:.1}", .{ pos.x.*, pos.y.* });
        }
        if (app.world.get(components.transform.RotationView, player_res.entity)) |rot| {
            try debug.setFmt("player.rot", "{d:.1}, {d:.1}", .{ rot.target_teta.*, rot.teta.* });
        }
    }
}

pub fn renderDebugSystem(app: *core.App) !void {
    const debug = app.getResource(resources.DebugState).?;
    if (!debug.enabled) return;
    renderBoxes(app);
    renderColliders(app);
    renderWalkables(app);
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
    var it_texture = app.world.query(&[_]type{ components.transform.Position, components.render.Texture, components.world.Room });
    while (it_texture.next()) |_| {
        const pos = it_texture.get(components.transform.PositionView);
        const texture_name = it_texture.getAuto(components.render.Texture).name;
        const rm = it_texture.get(components.world.RoomView);

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
    var it_render = app.world.query(&[_]type{ components.transform.Position, components.render.RenderInto, components.world.Room });
    while (it_render.next()) |_| {
        const pos = it_render.get(components.transform.PositionView);
        const into = it_render.getAuto(components.render.RenderInto).into;
        const rm = it_render.get(components.world.RoomView);

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
    var it = app.world.query(&[_]type{ components.collision.ColliderLine, components.world.Room });
    while (it.next()) |_| {
        const line = it.get(components.collision.ColliderLineView);
        const rm = it.get(components.world.RoomView);

        if (rm.id.* != current_room_id) continue;

        const from: rl.Vector2 = .{ .x = line.x0.*, .y = line.y0.* };
        const to: rl.Vector2 = .{ .x = line.x1.*, .y = line.y1.* };
        rl.DrawLineEx(from, to, 4.0, rl.GREEN);
    }
    var circle_it = app.world.query(&[_]type{ components.transform.Position, components.collision.ColliderCircle, components.world.Room });
    while (circle_it.next()) |_| {
        const pos = circle_it.get(components.transform.PositionView);
        const col = circle_it.get(components.collision.ColliderCircleView);
        const rm = circle_it.get(components.world.RoomView);

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

fn renderWalkables(app: *core.App) void {
    const room_mgr = app.getResource(level_resources.RoomManager) orelse return;
    const current_room_id = room_mgr.current orelse return;
    const bounds = room_mgr.getBounds(current_room_id) orelse return;
    const grid = room_mgr.getGrid(current_room_id) orelse return;

    const cell_size = level_resources.RoomManager.cell_size;
    const alpha: u8 = 50;
    const walk_color = rl.Color{ .r = 0, .g = 255, .b = 0, .a = alpha };
    const block_color = rl.Color{ .r = 255, .g = 0, .b = 0, .a = alpha };

    for (0..grid.h) |y| {
        for (0..grid.w) |x| {
            const idx = y * grid.w + x;
            const rx = bounds.x + @as(f32, @floatFromInt(x)) * cell_size;
            const ry = bounds.y + @as(f32, @floatFromInt(y)) * cell_size;
            const rect = rl.Rectangle{
                .x = rx,
                .y = ry,
                .width = cell_size,
                .height = cell_size,
            };
            if (grid.walkables[idx]) {
                rl.DrawRectangleLinesEx(rect, 1.5, walk_color);
            } else {
                rl.DrawRectangleRec(rect, block_color);
            }
        }
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

fn interpolatedPositionX(pos: components.transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: components.transform.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_y.*, pos.y.*, alpha);
}

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
const std = @import("std");

const game = @import("game");
const components = game.components;
const resources = game.plugins.debug.resources;
const core_resources = game.plugins.core.resources;
const level_resources = game.plugins.level.resources;
const render_resources = game.plugins.render.resources;
const player_resources = game.plugins.player.resources;
const render = game.plugins.render;
