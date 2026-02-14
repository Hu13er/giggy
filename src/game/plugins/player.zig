pub const PlayerPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        const render_targets = app.getResource(resources.RenderTargets).?;
        _ = try render_targets.loadRenderTexture("player", 64, 64);
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;

        const loco_animset = blk: {
            const val = assets_mgr.configValuePath(
                "animations",
                &.{ "locomotion", "greenman" },
            ).?;
            break :blk try json.parseFromValue(comps.LocomotionAnimSet, app.gpa, val, .{});
        };
        defer loco_animset.deinit();

        const player = try app.world.spawn(.{
            comps.Position{ .x = 70, .y = 70, .prev_x = 70, .prev_y = 70 },
            comps.Velocity{ .x = 0, .y = 0 },
            comps.ColliderCircle{ .radius = 16.0, .mask = 1 },
            comps.Rotation{ .teta = 0, .prev_teta = 0, .target_teta = 0, .turn_speed_deg = 360.0 * 3 },
            comps.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
            comps.RenderInto{ .into = "player" },
            comps.Animation{ .index = 0, .frame = 0, .acc = 0, .speed = 0 },
            loco_animset.value,
            comps.LocomotionAnimState{ .moving = false },
        });
        _ = try app.insertResource(resources.Player, .{ .entity = player });

        try app.addSystem(.update, PlayerInputSystem);
    }
};

const PlayerInputSystem = struct {
    pub const provides: []const []const u8 = &.{"input"};

    pub fn run(app: *core.App) !void {
        const world = &app.world;
        const player = app.getResource(resources.Player).?.entity;
        const vel = world.get(comps.VelocityView, player).?;
        const rot = world.get(comps.RotationView, player).?;
        var x: f32 = 0;
        var y: f32 = 0;

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
};

const std = @import("std");
const json = std.json;

const engine = @import("engine");
const core = engine.core;
const rl = engine.rl;
const xmath = engine.math;
const ecs = engine.ecs;

const comps = @import("../components.zig");
const resources = @import("../resources.zig");
