pub fn playerInputSystem(app: *core.App) !void {
    const time_resc = app.getResource(core.Time).?;
    const input_resc = app.getResource(resources.PlayerInput).?;

    var move_axis: xmath.Vec2 = .{ .x = 0, .y = 0 };

    if (rl.IsKeyDown(rl.KEY_D)) {
        move_axis.x = 1;
    } else if (rl.IsKeyDown(rl.KEY_A)) {
        move_axis.x = -1;
    }
    if (rl.IsKeyDown(rl.KEY_W)) {
        move_axis.y = -1;
    } else if (rl.IsKeyDown(rl.KEY_S)) {
        move_axis.y = 1;
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
            move_axis.x = gx;
            move_axis.y = gy;
        }
    }

    input_resc.queue(.{
        .tick = time_resc.tick,
        .move = move_axis.normalize(),
    });
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const xmath = engine.math;
const rl = engine.raylib;
const game = @import("game");
const components = game.components;
const resources = game.plugins.input.resources;
