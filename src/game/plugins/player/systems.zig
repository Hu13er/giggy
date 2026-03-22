const PLAYER_SPEED: f32 = 250;

/// name: playerInputSystem
/// side: server
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

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const game = @import("game");
const components = game.components;
const resources = game.plugins.player.resources;
const fade_resources = game.plugins.fade.resources;
