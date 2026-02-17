pub fn playerInputSystem(app: *core.App) !void {
    const world_ref = &app.world;
    const player_entity = app.getResource(resources.Player).?.entity;
    const vel = world_ref.get(transform.VelocityView, player_entity).?;
    const rot = world_ref.get(transform.RotationView, player_entity).?;
    var x: f32 = 0;
    var y: f32 = 0;

    if (app.getResource(fade_resources.ScreenFade)) |fade| {
        if (fade.active()) {
            vel.x.* = 0;
            vel.y.* = 0;
            return;
        }
    }

    if (rl.IsKeyDown(rl.KEY_D)) {
        x = 10;
    } else if (rl.IsKeyDown(rl.KEY_A)) {
        x = -10;
    }
    if (rl.IsKeyDown(rl.KEY_W)) {
        y = -10;
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        y = 10;
    }

    if (rl.IsGamepadAvailable(0)) {
        var gx = rl.GetGamepadAxisMovement(0, rl.GAMEPAD_AXIS_LEFT_X);
        var gy = rl.GetGamepadAxisMovement(0, rl.GAMEPAD_AXIS_LEFT_Y);
        const deadzone: f32 = 0.2;
        if (@abs(gx) < deadzone) gx = 0;
        if (@abs(gy) < deadzone) gy = 0;

        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_LEFT)) gx = -1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_RIGHT)) gx = 1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_UP)) gy = -1;
        if (rl.IsGamepadButtonDown(0, rl.GAMEPAD_BUTTON_LEFT_FACE_DOWN)) gy = 1;

        if (@abs(gx) > 0 or @abs(gy) > 0) {
            x = gx;
            y = gy;
        }
    }

    const l = std.math.sqrt(x * x + y * y);
    if (l > 0.1) {
        x = x / l * 250.0;
        y = y / l * 250.0;

        const angle = std.math.atan2(y, -x);
        rot.target_teta.* = std.math.radiansToDegrees(angle) - 45.0;
    }
    vel.x.* = x;
    vel.y.* = y;
}

pub fn playerSpawnSystem(app: *core.App) !void {
    var it_player = app.world.query(&[_]type{
        player_comp.Player,
        transform.Position,
        transform.Rotation,
        world_comp.Room,
    });
    while (it_player.next()) |_| {
        const pos = it_player.get(transform.PositionView);
        const rot = it_player.get(transform.RotationView);
        const player_view = it_player.get(player_comp.PlayerView);
        const room = it_player.get(world_comp.RoomView);
        if (!player_view.just_spawned.*) continue;

        const desired_spawn_id = player_view.spawn_id.*;
        var best_fallback_id: ?u8 = null;
        var best_fallback_x: f32 = 0;
        var best_fallback_y: f32 = 0;
        var found_x: f32 = 0;
        var found_y: f32 = 0;
        var found = false;

        var it_spawn = app.world.query(&[_]type{ world_comp.SpawnPoint, transform.Position, world_comp.Room });
        while (it_spawn.next()) |_| {
            const sp = it_spawn.get(world_comp.SpawnPointView);
            const sp_pos = it_spawn.get(transform.PositionView);
            const sp_room = it_spawn.get(world_comp.RoomView);
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
const player_comp = game.components.player;
const transform = game.components.transform;
const world_comp = game.components.world;
const resources = game.plugins.player.resources;
const fade_resources = game.plugins.fade.resources;
