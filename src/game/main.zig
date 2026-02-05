const screenWidth: u32 = 800;
const screenHeight: u32 = 600;

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "Giggy: Blob Splits");
    defer rl.CloseWindow();
    rl.SetTargetFPS(160);

    // init ecs
    const allocator = std.heap.c_allocator;
    var world = try ecs.World.init(allocator);
    defer world.deinit();

    // load resources
    const textures = [_]rl.Texture2D{
        rl.LoadTexture("map.png"),
    };
    defer for (textures) |t| rl.UnloadTexture(t);

    const models = [_]rl.Model{
        rl.LoadModel("gltf/greenman.glb"),
    };
    defer for (models) |m| rl.UnloadModel(m);

    const shaders = [_]rl.Shader{
        rl.LoadShader(
            "shaders/glsl330/skinning.vs",
            "shaders/glsl330/skinning.fs",
        ),
    };
    defer for (shaders) |s| rl.UnloadShader(s);

    models[0].materials[1].shader = shaders[0];

    const model_animations = [_][]rl.ModelAnimation{
        loadModelAnimations("gltf/greenman.glb"),
    };
    defer for (model_animations) |ma| unloadModelAnimations(ma);

    const render_textures = [_]rl.RenderTexture{
        rl.LoadRenderTexture(64, 64),
    };
    defer for (render_textures) |r| rl.UnloadRenderTexture(r);

    var camera = rl.Camera2D{
        .offset = rl.Vector2{
            .x = @as(f32, @floatFromInt(screenWidth)) / 2.0,
            .y = @as(f32, @floatFromInt(screenHeight)) / 2.0,
        },
        .target = rl.Vector2{ .x = 0, .y = 0 },
        .rotation = 0.0,
        .zoom = 1.0,
    };
    const camera3d = rl.Camera3D{
        .position = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
        .target = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .fovy = 3.0,
        .projection = rl.CAMERA_ORTHOGRAPHIC,
    };

    const player = try world.spawn(.{
        comps.Position{ .x = 10, .y = 10 },
        comps.Velocity{ .x = 0, .y = 0 },
        comps.Rotation{ .teta = 0 },
        comps.Model3D{ .index = 0, .render_texture = 0, .mesh = 0, .material = 1 },
        comps.Animation{ .index = 0, .animation_index = 0, .frame = 0 },
        comps.MoveAnimation{ .idle = 0, .run = 2 },
    });

    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        {
            const player_vel = world.get(comps.VelocityView, player).?;
            const player_rot = world.get(comps.RotationView, player).?;

            var x: f32 = 0;
            var y: f32 = 0;
            if (rl.IsKeyDown(rl.KEY_D)) {
                x = 10;
            } else if (rl.IsKeyDown(rl.KEY_A)) {
                x = -10;
            } else {
                x = 0;
            }
            if (rl.IsKeyDown(rl.KEY_W)) {
                y = -10;
            } else if (rl.IsKeyDown(rl.KEY_S)) {
                y = 10;
            } else {
                y = 0;
            }
            const l = std.math.sqrt(x * x + y * y);
            if (l > 0.1) {
                x = x / l * 100.0;
                y = y / l * 100.0;

                const angle = std.math.atan2(y, -x);
                player_rot.teta.* = std.math.radiansToDegrees(angle) - 45.0;
            }
            player_vel.x.* = x;
            player_vel.y.* = y;
        }
        {
            // pos += vel
            var it = world.query(&[_]type{ comps.Position, comps.Velocity });
            while (it.next()) |_| {
                const pos = it.get(comps.PositionView);
                const vel = it.get(comps.VelocityView);
                pos.x.* += dt * vel.x.*;
                pos.y.* += dt * vel.y.*;
            }
        }
        {
            // update camera target
            const player_pos = world.get(comps.PositionView, player).?;

            const w = @as(f32, @floatFromInt(screenWidth));
            const h = @as(f32, @floatFromInt(screenHeight));

            var x = player_pos.x.*;
            const min_x = w / 2.0;
            const max_x = @as(f32, @floatFromInt(textures[0].width)) - w / 2.0;
            x = @max(x, min_x);
            x = @min(x, max_x);

            var y = player_pos.y.*;
            const min_y = @as(f32, @floatFromInt(screenHeight)) / (2.0);
            const max_y = @as(f32, @floatFromInt(textures[0].height)) - h / 2.0;
            y = @max(y, min_y);
            y = @min(y, max_y);

            camera.target = .{ .x = x, .y = y };
        }
        {
            // animate moving objects
            var it = world.query(&[_]type{ comps.Velocity, comps.MoveAnimation, comps.Animation });
            while (it.next()) |_| {
                const av = it.get(comps.AnimationView);
                const vv = it.get(comps.VelocityView);
                const mav = it.get(comps.MoveAnimationView);
                if (@abs(vv.x.*) > 0.1 or @abs(vv.y.*) > 0.1) {
                    av.animation_index.* = mav.run.*;
                } else {
                    av.animation_index.* = mav.idle.*;
                }
            }
        }
        {
            // animate moving objects
            var it = world.query(&[_]type{ comps.Animation, comps.Velocity, comps.MoveAnimation });
            while (it.next()) |_| {
                const av = it.get(comps.AnimationView);
                const vv = it.get(comps.VelocityView);
                const mav = it.get(comps.MoveAnimationView);
                if (@abs(vv.x.*) > 0.1 or @abs(vv.y.*) > 0.1) {
                    av.animation_index.* = mav.run.*;
                } else {
                    av.animation_index.* = mav.idle.*;
                }
            }
        }
        {
            // 3d model animations
            var it = world.query(&[_]type{ comps.Model3D, comps.Animation });
            while (it.next()) |_| {
                const mv = it.get(comps.Model3DView);
                const am = it.get(comps.AnimationView);

                const model = models[mv.index.*];
                const anim = model_animations[am.index.*][am.animation_index.*];
                const new_current = (am.frame.* + 1) % @as(usize, @intCast(anim.frameCount));
                am.frame.* = new_current;
                rl.UpdateModelAnimationBones(model, anim, @intCast(new_current));
            }
        }
        {
            // render 3ds
            var it = world.query(&[_]type{ comps.Model3D, comps.Rotation });
            while (it.next()) |_| {
                const mv = it.get(comps.Model3DView);
                const rv = it.get(comps.RotationView);

                rl.BeginTextureMode(render_textures[mv.render_texture.*]);
                rl.ClearBackground(rl.BLANK);
                rl.BeginMode3D(camera3d);
                rl.DrawModelEx(
                    models[mv.index.*],
                    rl.Vector3{ .x = 0, .y = 0, .z = 0 },
                    rl.Vector3{ .x = 0, .y = 1, .z = 0 }, // rotate around Y
                    rv.teta.*,
                    rl.Vector3{ .x = 1, .y = 1, .z = 1 },
                    rl.WHITE,
                );
                // rl.DrawGrid(10, 1.0);
                rl.EndMode3D();
                rl.EndTextureMode();
            }
        }

        // render main scene
        rl.BeginDrawing();
        rl.ClearBackground(rl.GRAY);

        rl.BeginMode2D(camera);
        rl.DrawTexture(textures[0], 0, 0, rl.WHITE);
        {
            var it = world.query(&[_]type{ comps.Position, comps.Model3D });
            while (it.next()) |_| {
                const pos = it.get(comps.PositionView);
                const model = it.get(comps.Model3DView);
                const render_texture = render_textures[model.render_texture.*];
                const src = rl.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @as(f32, @floatFromInt(render_texture.texture.width)),
                    .height = -@as(f32, @floatFromInt(render_texture.texture.height)),
                };
                rl.DrawTextureRec(
                    render_texture.texture,
                    src,
                    rl.Vector2{ .x = pos.x.*, .y = pos.y.* },
                    rl.WHITE,
                );
            }
        }
        rl.EndMode2D();

        rl.DrawFPS(10, screenHeight - 30);
        rl.EndDrawing();
    }
}

fn loadModelAnimations(path: [*c]const u8) []rl.ModelAnimation {
    var count: c_int = undefined;
    const ptr = rl.LoadModelAnimations(path, &count);
    return ptr[0..@as(usize, @intCast(count))];
}

fn unloadModelAnimations(items: []rl.ModelAnimation) void {
    rl.UnloadModelAnimations(items.ptr, @intCast(items.len));
}

const std = @import("std");
const rl = @import("../rl.zig").rl;
const rm = @import("../rl.zig").rm;
const ecs = @import("../ecs.zig");
const comps = @import("components.zig");
