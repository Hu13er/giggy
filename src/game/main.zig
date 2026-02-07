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

    _ = try resc.loadRenderTexture("player", 64, 64);

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

    const lvl1 = resc.jsons.get("level1").?;
    for (lvl1.value.images) |img| {
        if (img.index == 0) continue; // dont load backgorund
        assert(resc.textures.getPtr(img.name) != null);
        _ = try world.spawn(.{
            comps.Position{ .x = img.position.x, .y = img.position.y },
            comps.WidthHeight{ .w = img.width, .h = img.height },
            comps.Texture{ .name = img.name },
        });
    }
    for (lvl1.value.polygons) |poly| {
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

    var command_buffer = try ecs.CommandBuffer.init(allocator);
    var to_render = try systems.RenderableList.initCapacity(allocator, 4);
    defer to_render.deinit(allocator);
    // main loop
    while (!rl.WindowShouldClose()) {
        const dt = rl.GetFrameTime();
        const ctx = SystemCtx{
            .resc = &resc,
            .world = &world,
            .cb = &command_buffer,
            .dt = dt,
        };

        const debug = systems.updateDebugMode(ctx);
        systems.playerInput(ctx, player);
        systems.updatePositions(ctx);
        systems.cameraOnObject(ctx, &camera, player);
        systems.animateMovingObjects(ctx);
        systems.upldate3dModelAnimations(ctx);
        systems.render3dModels(ctx);

        rl.BeginDrawing();
        rl.ClearBackground(rl.GRAY);
        rl.BeginMode2D(camera);
        // render main scene
        systems.renderBackground(ctx, "map");
        try systems.collectRenderables(ctx, allocator, &to_render);
        systems.renderRenderables(ctx, &to_render);
        to_render.items.len = 0;
        if (debug) {
            systems.renderBoxes(ctx);
            systems.renderColliders(ctx);
        }
        rl.EndMode2D();
        // render gui
        if (debug) rl.DrawFPS(10, screenHeight - 30);
        rl.EndDrawing();
    }
}

const std = @import("std");
const assert = std.debug.assert;
const rl = @import("../rl.zig").rl;
const rm = @import("../rl.zig").rm;

const ecs = @import("../ecs.zig");
const comps = @import("components.zig");
const systems = @import("systems.zig");
const map_loader = @import("map_loader.zig");

const Resources = @import("resources.zig");
