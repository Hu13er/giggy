const PLAYER_SPEED: f32 = 250;

/// name: playerInputSystem
/// side: server
/// semi-DEPRECATED
pub fn playerInputSystem(app: *core.App) !void {
    const input_resc = app.getResource(game.plugins.input.resources.PlayerInput).?;

    const player_entity = app.getResource(resources.Player).?.entity;
    const vel = app.world.get(components.transform.VelocityView, player_entity).?;
    const rot = app.world.get(components.transform.RotationView, player_entity).?;

    if (app.getResource(fade_resources.ScreenFade)) |fade| {
        if (fade.active()) {
            vel.x.* = 0;
            vel.y.* = 0;
            return;
        }
    }

    const move_axis = input_resc.current.move.scale(PLAYER_SPEED);
    if (move_axis.abs() > 0.1) {
        const angle = std.math.atan2(move_axis.y, -move_axis.x);
        rot.target_teta.* = std.math.radiansToDegrees(angle) - 45.0;
        vel.x.* = move_axis.x;
        vel.y.* = move_axis.y;
    } else {
        vel.x.* = 0;
        vel.y.* = 0;
    }
}

pub fn playerSpawnSystem(app: *core.App) !void {
    var it_player = app.world.query(&[_]type{
        components.player.Player,
        components.transform.Position,
        components.transform.Rotation,
        components.world.Room,
    });
    while (it_player.next()) |_| {
        const pos = it_player.get(components.transform.PositionView);
        const rot = it_player.get(components.transform.RotationView);
        const player_view = it_player.get(components.player.PlayerView);
        const room = it_player.get(components.world.RoomView);
        if (!player_view.just_spawned.*) continue;

        const desired_spawn_id = player_view.spawn_id.*;
        var best_fallback_id: ?u8 = null;
        var best_fallback_x: f32 = 0;
        var best_fallback_y: f32 = 0;
        var found_x: f32 = 0;
        var found_y: f32 = 0;
        var found = false;

        var it_spawn = app.world.query(&[_]type{ components.world.SpawnPoint, components.transform.Position, components.world.Room });
        while (it_spawn.next()) |_| {
            const sp = it_spawn.get(components.world.SpawnPointView);
            const sp_pos = it_spawn.get(components.transform.PositionView);
            const sp_room = it_spawn.get(components.world.RoomView);
            if (sp_room.id.* != room.id.*) continue;

            if (best_fallback_id == null or sp.id.* < best_fallback_id.?) {
                best_fallback_id = sp.id.*;
                best_fallback_x = sp_pos.x.*;
                best_fallback_y = sp_pos.y.*;
            }

            if (desired_spawn_id != 0 and sp.id.* == desired_spawn_id) {
                found_x = sp_pos.x.*;
                found_y = sp_pos.y.*;
                found = true;
                break;
            }
        }

        const x = if (found) found_x else if (best_fallback_id != null) best_fallback_x else pos.x.*;
        const y = if (found) found_y else if (best_fallback_id != null) best_fallback_y else pos.y.*;

        rot.teta.* = 45;
        rot.target_teta.* = 45;
        pos.x.* = x;
        pos.y.* = y;
        pos.prev_x.* = x;
        pos.prev_y.* = y;
        player_view.just_spawned.* = false;
        player_view.spawn_id.* = 0;
    }
}

pub fn playerSyncSystem(app: *core.App) !void {
    const sync_resc = app.getResource(game.plugins.player.resources.SyncMap).?;
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;

    var cb = try engine.ecs.CommandBuffer.init(app.gpa);
    defer cb.deinit();

    const loco_animset = blk: {
        const val = assets_mgr.configValuePath(
            "animations",
            &.{ "locomotion", "greenman" },
        ).?;
        break :blk try std.json.parseFromValue(components.animation.LocomotionAnimSet, app.gpa, val, .{});
    };
    defer loco_animset.deinit();

    const ServerViews = [_]type{
        components.transform.PositionView,
        components.transform.VelocityView,
        components.transform.RotationView,
        components.collision.ColliderCircleView,
        components.world.RoomView,
    };

    var server_it = app.world.query(&[_]type{
        engine.net.Sync,
        components.player.Player,
    });
    while (server_it.next()) |server_entity| {
        var client_entity_id: engine.ecs.Entity = undefined;
        if (sync_resc.map.get(server_entity)) |current_client_entity| {
            // Update with new data from server
            inline for (ServerViews) |V| {
                if (server_it.getOrNull(V)) |server_view| {
                    // const server_view = server_it.getOrNull(V) orelse continue;
                    // See if the componet already exists for the client player.
                    // Cannot use app.world.get() here since its null value determines a non-existent entity,
                    // not a non-existent component! Hence, we use archetypes to determine existence of a component.
                    const arch = app.world.archetypeOf(current_client_entity).?;
                    if (arch.meta.hasComponent(V.Of)) {
                        // Case 1: the component exists. Applying new values to the component.
                        const client_view = app.world.get(V, current_client_entity).?;
                        inline for (std.meta.fields(V.Of)) |f| {
                            @field(client_view, f.name).* = @field(server_view, f.name).*;
                        }
                    } else {
                        // Case 2: the component does not exist. Assigning a new component to the client player.
                        try cb.assign(current_client_entity, .{
                            engine.ecs.util.copyView(V, server_view),
                        });
                    }
                }
            }
            client_entity_id = current_client_entity;
        } else {
            // Player does not exist on client. Create a new client player.
            const client_entity_reserved = app.world.reserveEntity();
            const bundle = ClientBundle{
                .model3d = components.render.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
                .render_into = components.render.RenderInto{ .into = "player" },
                .animation = components.animation.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
                .locomotion_anim_set = loco_animset.value,
                .locomotion_anim_state = components.animation.LocomotionAnimState{ .moving = false },
            };
            try cb.spawn(client_entity_reserved, bundle);
            inline for (ServerViews) |V| {
                if (server_it.getOrNull(V)) |v| {
                    try cb.assign(client_entity_reserved, .{
                        engine.ecs.util.copyView(V, v),
                    });
                }
            }
            client_entity_id = client_entity_reserved;
        }

        try cb.flush(&app.world);
        try sync_resc.map.put(server_entity, client_entity_id);
    }

    const server_entities = sync_resc.map.keys();

    var deleted_keys = try std.ArrayList(engine.ecs.Entity).initCapacity(app.gpa, 4);
    defer deleted_keys.deinit(app.gpa);
    for (server_entities) |e| {
        if (app.world.get(components.player.PlayerView, e) == null) {
            // We have a redundant server player in our sync map that server has no longer sent us.
            // We'll need to remove it from the map.
            try deleted_keys.append(app.gpa, e);
        }
    }
    for (deleted_keys.items) |k| _ = sync_resc.map.swapRemove(k);

    // Our work is KIRI perfect. -Xy6ep
}

pub const ClientBundle = struct {
    model3d: components.render.Model3D,
    render_into: components.render.RenderInto,
    animation: components.animation.Animation,
    locomotion_anim_set: components.animation.LocomotionAnimSet,
    locomotion_anim_state: components.animation.LocomotionAnimState,
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const game = @import("game");
const components = game.components;
const resources = game.plugins.player.resources;
const fade_resources = game.plugins.fade.resources;
