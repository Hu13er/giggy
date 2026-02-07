const screenWidth: u32 = 800;
const screenHeight: u32 = 600;

pub const SystemCtx = struct {
    resc: *Resources,
    world: *ecs.World,
    cb: *ecs.CommandBuffer,
    dt: f32,
};

pub fn main() !void {
    rl.InitWindow(screenWidth, screenHeight, "Giggy: Blob Splits");
    defer rl.CloseWindow();
    const hz = rl.GetMonitorRefreshRate(rl.GetCurrentMonitor());
    rl.SetTargetFPS(hz);
    // rl.SetTargetFPS(160);

    // init ecs
    const allocator = std.heap.c_allocator;

    var world = try ecs.World.init(allocator);
    defer world.deinit();

    var resc = try Resources.init(allocator);
    defer resc.deinit();

    _ = try resc.loadTexture("map", "resources/map.png");
    _ = try resc.loadTexture("abol", "resources/abol.png");
    _ = try resc.loadTexture("wall1", "resources/wall1.png");
    _ = try resc.loadTexture("wall2", "resources/wall2.png");

    const greenman_model = try resc.loadModel("greenman", "resources/gltf/greenman.glb");
    const skinning_shader = try resc.loadShader(
        "skinning",
        "resources/shaders/glsl330/skinning.vs",
        "resources/shaders/glsl330/skinning.fs",
    );
    greenman_model.model.materials[1].shader = skinning_shader.*;

    _ = try resc.loadJson("level1", "resources/json/layers.json");

    const render_textures = [_]rl.RenderTexture{
        rl.LoadRenderTexture(64, 64),
    };
    defer for (render_textures) |r| rl.UnloadRenderTexture(r);

    // setup camera
    var camera = rl.Camera2D{
        .offset = rl.Vector2{
            .x = @as(f32, @floatFromInt(screenWidth)) / 2.0,
            .y = @as(f32, @floatFromInt(screenHeight)) / 2.0,
        },
        .target = rl.Vector2{ .x = 0, .y = 0 },
        .rotation = 0.0,
        .zoom = 1.0,
    };

    _ = try resc.loadRenderTexture("player", 64, 64);
    // init entities
    const player = try world.spawn(.{
        comps.Position{ .x = 70, .y = 70 },
        comps.Velocity{ .x = 0, .y = 0 },
        comps.Rotation{ .teta = 0 },
        comps.Model3D{ .name = "greenman", .render_texture = 0, .mesh = 0, .material = 1 },
        comps.RenderInto{ .into = "player" },
        comps.Animation{ .index = 0, .frame = 0 },
        comps.MoveAnimation{ .idle = 0, .run = 2 },
    });

    var json_it = resc.jsons.valueIterator();
    while (json_it.next()) |js| {
        for (js.value.images) |img| {
            if (img.index == 0) continue; // dont load backgorund
            assert(resc.textures.getPtr(img.name) != null);
            _ = try world.spawn(.{
                comps.Position{ .x = img.position.x, .y = img.position.y },
                comps.WidthHeight{ .w = img.width, .h = img.height },
                comps.Texture{ .name = img.name },
            });
        }
        for (js.value.polygons) |poly| {
            if (!std.mem.eql(u8, poly.name, "edge")) continue;
            var last = poly.vertices[0];
            for (poly.vertices[1..]) |v| {
                _ = try world.spawn(.{
                    comps.Line{
                        .x0 = last.x,
                        .y0 = last.y,
                        .x1 = v.x,
                        .y1 = v.y,
                    },
                });
                last.x = v.x;
                last.y = v.y;
            }
            if (poly.closed) {
                _ = try world.spawn(.{
                    comps.Line{
                        .x0 = last.x,
                        .y0 = last.y,
                        .x1 = poly.vertices[0].x,
                        .y1 = poly.vertices[0].y,
                    },
                });
            }
        }
    }

    var command_buffer = try ecs.CommandBuffer.init(allocator);
    // main loop
    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        const ctx = SystemCtx{
            .resc = &resc,
            .world = &world,
            .cb = &command_buffer,
            .dt = dt,
        };

        systems.playerInput(ctx, player);
        systems.updatePositions(ctx);
        systems.cameraOnObject(ctx, &camera, player);
        systems.animateMovingObjects(ctx);
        systems.upldate3dModelAnimations(ctx);
        systems.render3dModels(ctx);

        // render main scene
        rl.BeginDrawing();
        rl.ClearBackground(rl.GRAY);

        rl.BeginMode2D(camera);

        const Renderable = struct {
            x: f32,
            y: f32,
            w: f32,
            h: f32,
            texture: rl.Texture,
            flip_h: bool,
        };
        var to_render = try std.ArrayList(Renderable).initCapacity(allocator, 4);
        defer to_render.deinit(allocator);
        {
            var it = world.query(&[_]type{ comps.Position, comps.WidthHeight, comps.Texture });
            while (it.next()) |_| {
                const pos = it.get(comps.PositionView);
                const wh = it.get(comps.WidthHeightView);
                const t = it.get(comps.TextureView);

                const texture = resc.textures.getPtr(t.name.*).?;

                try to_render.append(allocator, Renderable{
                    .x = pos.x.*,
                    .y = pos.y.*,
                    .w = wh.w.*,
                    .h = wh.h.*,
                    .flip_h = false,
                    .texture = texture.*,
                });
            }
        }
        {
            var it = world.query(&[_]type{ comps.Position, comps.Model3D });
            while (it.next()) |_| {
                const pos = it.get(comps.PositionView);
                const model = it.get(comps.Model3DView);
                const render_texture = render_textures[model.render_texture.*];

                const w = @as(f32, @floatFromInt(render_texture.texture.width));
                const h = @as(f32, @floatFromInt(render_texture.texture.height));

                try to_render.append(allocator, Renderable{
                    .x = pos.x.* - h / 2.0,
                    .y = pos.y.* - w / 2.0,
                    .w = w,
                    .h = h,
                    .flip_h = true,
                    .texture = render_texture.texture,
                });
            }
        }
        std.sort.insertion(Renderable, to_render.items, {}, struct {
            fn lessThan(_: void, a: Renderable, b: Renderable) bool {
                if (a.y + a.h < b.y + b.h) return true;
                return false;
            }
        }.lessThan);

        const map = resc.textures.get("map").?;
        rl.DrawTexture(map, 0, 0, rl.WHITE);
        for (to_render.items) |r| {
            const flip: f32 = if (r.flip_h) -1 else 1;
            const src = rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = r.w,
                .height = r.h * flip,
            };
            rl.DrawTextureRec(r.texture, src, .{ .x = r.x, .y = r.y }, rl.WHITE);

            const from: rl.Vector2 = .{ .x = 0, .y = r.y + r.h };
            const to: rl.Vector2 = .{ .x = 800.0, .y = r.y + r.h };
            rl.DrawLineEx(from, to, 4.0, rl.RED);
        }
        {
            // Draw edge lines
            var it = world.query(&[_]type{comps.Line});
            while (it.next()) |_| {
                const line = it.get(comps.LineView);
                const from: rl.Vector2 = .{ .x = line.x0.*, .y = line.y0.* };
                const to: rl.Vector2 = .{ .x = line.x1.*, .y = line.y1.* };
                rl.DrawLineEx(from, to, 4.0, rl.GREEN);
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
const debug = std.debug;
const assert = debug.assert;
const rl = @import("../rl.zig").rl;
const rm = @import("../rl.zig").rm;

const ecs = @import("../ecs.zig");
const comps = @import("components.zig");
const systems = @import("systems.zig");
const map_loader = @import("map_loader.zig");

const Resources = @import("resources.zig");
