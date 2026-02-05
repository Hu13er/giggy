const screenWidth: u32 = 800;
const screenHeight: u32 = 450;

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "Giggy: Blob Splits");
    defer rl.CloseWindow();
    rl.SetTargetFPS(160);

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.RAYWHITE);
        rl.DrawFPS(10, screenHeight - 30);
    }
}

const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});
const ecs = @import("ecs.zig");
