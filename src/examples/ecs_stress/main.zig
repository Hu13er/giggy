const std = @import("std");
const engine = @import("engine");
const ecs = engine.ecs;
const rl = engine.rl;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

const PositionView = struct {
    pub const Of = Position;
    x: *f32,
    y: *f32,
};

const VelocityView = struct {
    pub const Of = Velocity;
    x: *f32,
    y: *f32,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.InitWindow(800, 450, "ECS Stress");
    defer rl.CloseWindow();
    rl.SetTargetFPS(160);

    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var entity_count: usize = defaultEntityCount;
    var sim_steps_per_frame: u64 = defaultSimStepsPerFrame;
    try resetWorld(&world, allocator, entity_count);

    var sim_timer = try std.time.Timer.start();
    var stats_timer = try std.time.Timer.start();
    var sim_acc_ns: u64 = 0;
    var sim_acc_steps: u64 = 0;
    var last_ns_per_step: u64 = 0;

    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_UP)) {
            entity_count += entityStep;
            try resetWorld(&world, allocator, entity_count);
        } else if (rl.IsKeyPressed(rl.KEY_DOWN)) {
            if (entity_count > entityStep) {
                entity_count -= entityStep;
            }
            if (entity_count < minEntityCount) {
                entity_count = minEntityCount;
            }
            try resetWorld(&world, allocator, entity_count);
        } else if (rl.IsKeyPressed(rl.KEY_R)) {
            try resetWorld(&world, allocator, entity_count);
        }

        if (rl.IsKeyPressed(rl.KEY_RIGHT)) {
            sim_steps_per_frame += 1;
        } else if (rl.IsKeyPressed(rl.KEY_LEFT)) {
            sim_steps_per_frame = if (sim_steps_per_frame > 1) sim_steps_per_frame - 1 else 1;
        }

        sim_timer.reset();
        for (0..sim_steps_per_frame) |_| {
            stepSimulation(&world, sim_dt);
            sim_acc_steps += 1;
        }
        sim_acc_ns += sim_timer.read();

        if (stats_timer.read() >= stats_interval_ns) {
            last_ns_per_step = if (sim_acc_steps == 0) 0 else sim_acc_ns / sim_acc_steps;
            sim_acc_ns = 0;
            sim_acc_steps = 0;
            stats_timer.reset();
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawText(title, 20, 20, title_font, rl.DARKGRAY);
        drawStat(20, 70, "entities", world.count(), stats_font);
        drawStat(20, 105, "render_fps", @intCast(rl.GetFPS()), stats_font);
        drawStat(20, 140, "sim_steps_per_frame", sim_steps_per_frame, stats_font);
        drawStatNs(20, 175, "ns_per_sim_step", last_ns_per_step, stats_font);
        rl.DrawText(controls, 20, 220, controls_font, rl.DARKGRAY);
        rl.DrawText(explain_1, 20, 255, explain_font, rl.GRAY);
        rl.DrawText(explain_2, 20, 280, explain_font, rl.GRAY);
        rl.DrawText(explain_3, 20, 305, explain_font, rl.GRAY);
        rl.EndDrawing();
    }
}

fn resetWorld(world: *ecs.World, allocator: std.mem.Allocator, count: usize) !void {
    world.deinit();
    world.* = try ecs.World.init(allocator);
    try spawnEntities(world, count);
}

fn spawnEntities(world: *ecs.World, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        _ = try world.spawn(.{
            Position{ .x = @floatFromInt(i), .y = 0 },
            Velocity{ .x = 1.0, .y = 0.5 },
        });
    }
}

fn stepSimulation(world: *ecs.World, dt: f32) void {
    var it = world.query(&[_]type{ Position, Velocity });
    while (it.next()) |_| {
        const pos = it.get(PositionView);
        const vel = it.get(VelocityView);
        pos.x.* += vel.x.* * dt;
        pos.y.* += vel.y.* * dt;
    }
}

fn drawStat(x: i32, y: i32, label: []const u8, value: u64, font_size: i32) void {
    var buf: [128]u8 = undefined;
    var num_buf: [64]u8 = undefined;
    const num = formatU64Commas(&num_buf, value) catch format_error;
    const line = std.fmt.bufPrintZ(&buf, "{s}: {s}", .{ label, num }) catch format_error;
    rl.DrawText(line, x, y, font_size, rl.BLACK);
}

fn drawStatNs(x: i32, y: i32, label: []const u8, ns: u64, font_size: i32) void {
    var buf: [128]u8 = undefined;
    var num_buf: [64]u8 = undefined;
    const num = formatU64Commas(&num_buf, ns) catch format_error;
    const line = std.fmt.bufPrintZ(&buf, "{s}: {s} ns", .{ label, num }) catch format_error;
    rl.DrawText(line, x, y, font_size, rl.BLACK);
}

fn formatU64Commas(buf: []u8, value: u64) ![]const u8 {
    var digits: [32]u8 = undefined;
    const src = std.fmt.bufPrint(&digits, "{d}", .{value}) catch return error.NoSpaceLeft;
    const len = src.len;
    const comma_count = if (len > 3) (len - 1) / 3 else 0;
    const out_len = len + comma_count;
    if (buf.len < out_len) return error.NoSpaceLeft;

    var src_i: isize = @as(isize, @intCast(len)) - 1;
    var out_i: isize = @as(isize, @intCast(out_len)) - 1;
    var group: u8 = 0;
    while (src_i >= 0) : (src_i -= 1) {
        buf[@intCast(out_i)] = src[@intCast(src_i)];
        out_i -= 1;
        group += 1;
        if (group == 3 and src_i != 0) {
            buf[@intCast(out_i)] = ',';
            out_i -= 1;
            group = 0;
        }
    }
    return buf[0..out_len];
}

const defaultEntityCount: usize = 20_000;
const minEntityCount: usize = 10_000;
const entityStep: usize = 10_000;
const defaultSimStepsPerFrame: u64 = 1;
const sim_dt: f32 = 1.0 / 60.0;
const stats_interval_ns: u64 = 500 * std.time.ns_per_ms;

const title: [:0]const u8 = "ecs_stress (sim-only)";
const controls: [:0]const u8 = "UP/DOWN: entities  LEFT/RIGHT: sim steps  R: reset";
const explain_1: [:0]const u8 = "Test: updates Position += Velocity * dt for all entities.";
const explain_2: [:0]const u8 = "Sim runs multiple steps per frame; timing excludes rendering.";
const explain_3: [:0]const u8 = "ns_per_sim_step is average cost per sim step over a short window.";
const format_error: [:0]const u8 = "format error";

const title_font: i32 = 28;
const stats_font: i32 = 24;
const controls_font: i32 = 20;
const explain_font: i32 = 18;
