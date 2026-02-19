pub fn main() !void {
    const screen_width = 640;
    const screen_height = 480;

    rl.InitWindow(screen_width, screen_height, "Giggy: Path Finding Demo");
    defer rl.CloseWindow();
    const hz = rl.GetMonitorRefreshRate(rl.GetCurrentMonitor());
    rl.SetTargetFPS(hz);

    const allocator = std.heap.page_allocator;

    const cell_size: f32 = 32.0;
    const grid_width: usize = 20;
    const grid_height: usize = 15;

    const grid = try allocator.alloc(bool, grid_width * grid_height);
    defer allocator.free(grid);

    var pf = Pathfinder.initDefault(
        grid_width,
        grid_height,
        cell_size,
        grid,
    );

    // Mark all cells walkable by default.
    for (pf.grid, 0..) |*cell, i| {
        _ = i;
        cell.* = true;
    }

    // Add a simple wall in the middle of the grid.
    const wall_y: usize = grid_height / 2;
    for (5..15) |x| {
        const idx = wall_y * grid_width + x;
        pf.grid[idx] = false;
    }

    const start_world = Vec2{
        .x = cell_size * 1.5,
        .y = cell_size * 1.5,
    };

    var target_world = start_world;
    var path: ?[]Vec2 = null;
    defer if (path) |p| allocator.free(p);

    while (!rl.WindowShouldClose()) {
        // Update target from mouse position when left button is pressed.
        if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
            target_world = Vec2{
                .x = @as(f32, @floatFromInt(rl.GetMouseX())),
                .y = @as(f32, @floatFromInt(rl.GetMouseY())),
            };

            if (path) |old| allocator.free(old);
            const maybe_path = try pf.findPath(allocator, start_world, target_world);
            if (maybe_path) |new_path| {
                path = new_path;
            } else {
                path = null;
            }
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        // Draw grid and obstacles.
        for (0..grid_height) |y| {
            for (0..grid_width) |x| {
                const idx = y * grid_width + x;
                const is_walkable = pf.grid[idx];

                const rx = @as(f32, @floatFromInt(@as(i32, @intCast(x)))) * cell_size;
                const ry = @as(f32, @floatFromInt(@as(i32, @intCast(y)))) * cell_size;

                const rect = rl.Rectangle{
                    .x = rx,
                    .y = ry,
                    .width = cell_size,
                    .height = cell_size,
                };

                const color = if (is_walkable) rl.LIGHTGRAY else rl.DARKGRAY;
                rl.DrawRectangleRec(rect, color);
                rl.DrawRectangleLines(
                    @intFromFloat(rect.x),
                    @intFromFloat(rect.y),
                    @intFromFloat(rect.width),
                    @intFromFloat(rect.height),
                    rl.GRAY,
                );
            }
        }

        // Draw start and current target.
        rl.DrawCircleV(
            rl.Vector2{ .x = start_world.x, .y = start_world.y },
            6.0,
            rl.GREEN,
        );
        rl.DrawCircleV(
            rl.Vector2{ .x = target_world.x, .y = target_world.y },
            6.0,
            rl.RED,
        );

        // Draw path if we have one.
        if (path) |p| {
            if (p.len > 0) {
                var i: usize = 0;
                while (i < p.len) : (i += 1) {
                    const pos = p[i];
                    rl.DrawCircleV(
                        rl.Vector2{ .x = pos.x, .y = pos.y },
                        4.0,
                        rl.BLUE,
                    );
                }
            }
        }

        rl.DrawText(
            "Left click to set target. Blue dots show A* path.",
            10,
            screen_height - 30,
            16,
            rl.BLACK,
        );
    }
}

const std = @import("std");
const engine = @import("engine");
const xmath = engine.math;
const rl = engine.raylib;
const algo = engine.algo;
const Pathfinder = algo.path_finding.Pathfinder;
const Vec2 = xmath.Vec2;
