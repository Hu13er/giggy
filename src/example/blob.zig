const Position = struct {
    pub const cid = 1;
    x: f32,
    y: f32,
};

const Velocity = struct {
    pub const cid = 2;
    dx: f32,
    dy: f32,
};

const Radius = struct {
    pub const cid = 3;
    value: f32,
};

const BlobBundle = struct {
    pos: Position,
    vel: Velocity,
    radius: Radius,
};

const PositionView = struct {
    pub const Of = Position;
    x: *f32,
    y: *f32,
};

const VelocityView = struct {
    pub const Of = Velocity;
    dx: *f32,
    dy: *f32,
};

const RadiusView = struct {
    pub const Of = Radius;
    value: *f32,
};

pub fn main() !void {
    const screenWidth = 800;
    const screenHeight = 450;
    const playArea = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @as(f32, screenWidth),
        .height = @as(f32, screenHeight),
    };

    rl.InitWindow(screenWidth, screenHeight, "Giggy: Blob Splits");
    defer rl.CloseWindow();
    rl.SetTargetFPS(160);

    const allocator = std.heap.page_allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var command_buf = try ecs.CommandBuffer.init(allocator);
    defer command_buf.deinit();
    const rng_seed: u64 = @intCast(std.time.milliTimestamp());
    var prngs = std.Random.DefaultPrng.init(rng_seed);

    const initialBlobRadius: f32 = 8;
    const splitCfg = struct { minRadius: f32, factor: f32 }{
        .minRadius = 2,
        .factor = 0.8,
    };

    for (0..256) |i| {
        const pos = Position{
            .x = 100.0 + 100.0 * @as(f32, @floatFromInt(i)),
            .y = 200.0,
        };
        const vel = randomVelocity(&prngs);
        _ = try world.spawn(
            BlobBundle{
                .pos = pos,
                .vel = vel,
                .radius = Radius{ .value = initialBlobRadius },
            },
        );
    }

    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();

        var mover = world.query(&[_]type{ Position, Velocity, Radius });
        while (mover.next()) |entity| {
            const p = mover.get(PositionView);
            const v = mover.get(VelocityView);
            const r = mover.get(RadiusView);

            p.x.* += v.dx.* * dt;
            p.y.* += v.dy.* * dt;

            var bounced = false;
            if (p.x.* - r.value.* <= playArea.x) {
                p.x.* = playArea.x + r.value.*;
                v.dx.* *= -1;
                bounced = true;
            } else if (p.x.* + r.value.* >= playArea.x + playArea.width) {
                p.x.* = playArea.x + playArea.width - r.value.*;
                v.dx.* *= -1;
                bounced = true;
            }
            if (p.y.* - r.value.* <= playArea.y) {
                p.y.* = playArea.y + r.value.*;
                v.dy.* *= -1;
                bounced = true;
            } else if (p.y.* + r.value.* >= playArea.y + playArea.height) {
                p.y.* = playArea.y + playArea.height - r.value.*;
                v.dy.* *= -1;
                bounced = true;
            }

            if (bounced) {
                if (r.value.* >= splitCfg.minRadius * 2) {
                    const childRadius = r.value.* * splitCfg.factor;
                    r.value.* = childRadius;
                    const child = BlobBundle{
                        .pos = Position{ .x = p.x.*, .y = p.y.* },
                        .vel = randomVelocity(&prngs),
                        .radius = Radius{ .value = childRadius },
                    };
                    const e = world.reserveEntity();
                    try command_buf.spawn(e, child);
                } else {
                    try command_buf.despawn(entity);
                }
            }
        }

        try command_buf.flush(&world);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        var draw_it = world.query(&[_]type{ Position, Radius });
        while (draw_it.next()) |_| {
            const pos = draw_it.get(PositionView);
            const radius = draw_it.get(RadiusView);
            rl.DrawCircleV(
                rl.Vector2{ .x = pos.x.*, .y = pos.y.* },
                radius.value.*,
                rl.MAROON,
            );
        }

        var buf: [64]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buf, "items: {d}", .{world.count()});
        const text_ptr = @as([*c]const u8, text.ptr);
        rl.DrawText(text_ptr, 10, screenHeight - 60, 16, rl.BLUE);
        rl.DrawText("Buffers flush at sync points; blobs split on walls.", 10, 10, 16, rl.DARKGRAY);
        rl.DrawFPS(10, screenHeight - 30);
    }
}

fn randomVelocity(prng: *std.Random.Xoshiro256) Velocity {
    var rnd = prng.random();
    const base = 80.0 + rnd.float(f32) * 120.0;
    const ang = rnd.float(f32) * std.math.tau;
    return Velocity{
        .dx = base * std.math.cos(ang),
        .dy = base * std.math.sin(ang),
    };
}

const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const ecs = @import("../ecs.zig");
