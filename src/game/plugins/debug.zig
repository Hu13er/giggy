pub const DebugPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.DebugState, resources.DebugState.init(app.gpa));
        try app.addSystem(.update, UpdateDebugModeSystem);
        try app.addSystem(.update, UpdateDebugValuesSystem);
        try app.addSystem(.render, RenderDebugSystem);
        try app.addSystem(.render, RenderDebugOverlaySystem);
    }
};

const UpdateDebugModeSystem = struct {
    pub fn run(app: *core.App) !void {
        const debug = app.getResource(resources.DebugState).?;
        if (rl.IsKeyReleased(rl.KEY_F9)) {
            debug.enabled = !debug.enabled;
        }
    }
};

const UpdateDebugValuesSystem = struct {
    pub fn run(app: *core.App) !void {
        const debug = app.getResource(resources.DebugState).?;
        if (!debug.enabled) return;

        const time = app.getResource(core.Time).?;
        try debug.setFmt("time.dt", "{d:.4}", .{time.dt});
        try debug.setFmt("time.alpha", "{d:.2}", .{time.alpha});
        try debug.setFmt("world.entities", "{d}", .{app.world.count()});

        if (app.getResource(resources.Player)) |player| {
            if (app.world.get(comps.PositionView, player.entity)) |pos| {
                try debug.setFmt("player.pos", "{d:.1}, {d:.1}", .{ pos.x.*, pos.y.* });
            }
        }
    }
};

const RenderDebugSystem = struct {
    pub const provides: []const []const u8 = &.{render.LabelRenderPass};
    pub const after_ids_optional: []const []const u8 = &.{render.RenderablesSystemId};

    pub fn run(app: *core.App) !void {
        const debug = app.getResource(resources.DebugState).?;
        if (!debug.enabled) return;
        renderBoxes(app);
        renderColliders(app);
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
        var it = app.world.query(&[_]type{comps.ColliderLine});
        while (it.next()) |_| {
            const line = it.get(comps.ColliderLineView);
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
};

const RenderDebugOverlaySystem = struct {
    pub const provides: []const []const u8 = &.{render.LabelRenderOverlay};
    pub const after_all_labels: []const []const u8 = &.{render.LabelRenderEndMode2D};

    pub fn run(app: *core.App) !void {
        const debug = app.getResource(resources.DebugState).?;
        if (!debug.enabled) return;
        const screen = app.getResource(resources.Screen).?;
        const fps_y: c_int = @intCast(screen.height);
        rl.DrawFPS(10, fps_y - 30);
        drawDebugValues(debug, 10, 10, 20, 16, rl.WHITE);
    }
};

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

fn interpolatedPositionX(pos: comps.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_x.*, pos.x.*, alpha);
}

fn interpolatedPositionY(pos: comps.PositionView, alpha: f32) f32 {
    return engine.math.lerp(pos.prev_y.*, pos.y.*, alpha);
}

const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const std = @import("std");

const resources = @import("../resources.zig");
const render = @import("render.zig");
const comps = @import("../components.zig");
