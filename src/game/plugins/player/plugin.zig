/// ye kar:
/// 1. write a client_player component that handles player rendering on client side
/// 2. write a "spawn" component
/// 3. write a system using which the client syncs its own player entities via
///    server's incoming player data.
/// 4. This current plugin will have an additional system that'll be invoked
///    only when the plugin is run on client side.
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
            break :blk try json.parseFromValue(components.animation.LocomotionAnimSet, app.gpa, val, .{});
        };
        defer loco_animset.deinit();

        const player_entity = try app.world.spawn(.{
            // logic / server
            components.player.Player{ .id = 1, .just_spawned = true, .spawn_id = 0 },
            components.transform.Position{ .x = 70, .y = 70, .prev_x = 70, .prev_y = 70 },
            components.transform.Velocity{ .x = 0, .y = 0 },
            components.collision.ColliderCircle{ .radius = 16.0, .mask = 1 },
            components.transform.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 3 },
            level_resources.roomFromName("level1"),

            // render / client
            components.render.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
            components.render.RenderInto{ .into = "player" },
            components.animation.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
            loco_animset.value,
            components.animation.LocomotionAnimState{ .moving = false },
        });
        _ = try app.insertResource(resources.Player, .{ .entity = player_entity });

        const is_server = app.getResource(game.plugins.core.resources.IsServer).?;
        if (is_server.value) {
            //
        } else {
            try app.addSystem(.fixed_update, systems.playerSyncSystem, .{
                .provides = &.{"player.sync"},
                .after_all_labels = &.{"network.tick"},
            });
        }

        // try app.addSystem(.update, systems.playerInputSystem, .{
        //     .provides = &.{"input"},
        // });
        try app.addSystem(.fixed_update, systems.playerSpawnSystem, .{
            .provides = &.{"player.spawn"},
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
const components = game.components;
const level_resources = game.plugins.level.resources;
const resources = game.plugins.player.resources;
const render_resources = game.plugins.render.resources;
const systems = game.plugins.player.systems;
