pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        const render_targets = app.getResource(render_resources.RenderTargets).?;
        _ = try render_targets.loadRenderTexture("enemy", 64, 64);
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;

        const loco_animset = blk: {
            const val = assets_mgr.configValuePath(
                "animations",
                &.{ "locomotion", "greenman" },
            ).?;
            break :blk try json.parseFromValue(components.animation.LocomotionAnimSet, app.gpa, val, .{});
        };
        defer loco_animset.deinit();

        _ = try app.world.spawn(.{
            components.enemy.Enemy{ .id = 1, .speed = 180.0 },
            components.transform.Position{ .x = 200, .y = 200, .prev_x = 200, .prev_y = 200 },
            components.transform.Velocity{ .x = 0, .y = 0 },
            components.collision.ColliderCircle{ .radius = 16.0, .mask = 1 },
            components.transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 2 },
            components.render.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
            components.render.RenderInto{ .into = "enemy" },
            components.animation.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
            loco_animset.value,
            components.animation.LocomotionAnimState{ .moving = false },
            level_resources.roomFromName("level1"),
        });

        try app.addSystem(.fixed_update, systems.enemyChaseSystem, .{
            .provides = &.{"input"},
        });
    }
};

const engine = @import("engine");
const core = engine.core;
const std = @import("std");
const json = std.json;

const game = @import("game");
const components = game.components;
const level_resources = game.plugins.level.resources;
const render_resources = game.plugins.render.resources;
const systems = game.plugins.enemy.systems;
