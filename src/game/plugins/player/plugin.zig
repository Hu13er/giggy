pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        const render_targets = app.getResource(render_resources.RenderTargets).?;
        _ = try render_targets.loadRenderTexture("player", 64, 64);
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;

        const loco_animset = blk: {
            const val = assets_mgr.configValuePath(
                "animations",
                &.{ "locomotion", "greenman" },
            ).?;
            break :blk try json.parseFromValue(animation.LocomotionAnimSet, app.gpa, val, .{});
        };
        defer loco_animset.deinit();

        const player_entity = try app.world.spawn(.{
            player_comp.Player{ .id = 1, .just_spawned = true, .spawn_id = 0 },
            transform.Position{ .x = 70, .y = 70, .prev_x = 70, .prev_y = 70 },
            transform.Velocity{ .x = 0, .y = 0 },
            collision.ColliderCircle{ .radius = 16.0, .mask = 1 },
            transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 3 },
            render.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
            render.RenderInto{ .into = "player" },
            animation.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
            loco_animset.value,
            animation.LocomotionAnimState{ .moving = false },
            world.Room.init("level1"),
        });
        _ = try app.insertResource(resources.Player, .{ .entity = player_entity });

        try app.addSystem(.update, systems.playerInputSystem, .{
            .provides = &.{"input"},
        });
        try app.addSystem(.fixed_update, systems.playerSpawnSystem, .{
            .provides = &.{"spawn"},
            .after_all_labels = &.{"teleport"},
        });
    }
};

const std = @import("std");
const json = std.json;

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
const xmath = engine.math;
const ecs = engine.ecs;

const game = @import("game");
const player_comp = game.components.player;
const transform = game.components.transform;
const collision = game.components.collision;
const animation = game.components.animation;
const render = game.components.render;
const world = game.components.world;
const resources = game.plugins.player.resources;
const render_resources = game.plugins.render.resources;
const systems = game.plugins.player.systems;
