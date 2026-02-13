pub const LevelPlugin = struct {
    file_path: []const u8,

    pub fn build(self: @This(), app: *core.App) !void {
        const registry = app.getResource(engine.prefabs.Registry).?;
        try registerPrefabs(registry);
        try registry.spawnFromTiledFile(&app.world, std.heap.page_allocator, self.file_path);
    }
};

fn registerPrefabs(registry: *engine.prefabs.Registry) !void {
    try registry.register("wall1", makeImageFactory("wall1"));
    try registry.register("wall2", makeImageFactory("wall2"));
    try registry.register("abol", makeImageFactory("abol"));
    try registry.register("edge", edgeFactory);
}

fn makeImageFactory(comptime name: []const u8) engine.prefabs.Registry.PrefabFactory {
    return struct {
        fn factory(
            entity: ecs.Entity,
            world: *ecs.World,
            cb: *ecs.CommandBuffer,
            gpa: mem.Allocator,
            object: json.Value,
        ) !void {
            _ = world;
            _ = gpa;
            const obj = switch (object) {
                .object => |o| o,
                else => return,
            };

            const x = valueToF32(obj.get("x")) orelse return;
            const y = valueToF32(obj.get("y")) orelse return;
            const w = valueToF32(obj.get("width")) orelse return;
            const h = valueToF32(obj.get("height")) orelse return;

            try cb.spawnBundle(entity, Bundle, .{
                .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
                .wh = .{ .w = w, .h = h },
                .tex = .{ .name = name },
            });
        }
    }.factory;
}

fn edgeFactory(
    entity: ecs.Entity,
    world: *ecs.World,
    cb: *ecs.CommandBuffer,
    gpa: mem.Allocator,
    object: json.Value,
) !void {
    _ = gpa;
    const obj = switch (object) {
        .object => |o| o,
        else => return,
    };

    const base_x = valueToF32(obj.get("x")) orelse 0;
    const base_y = valueToF32(obj.get("y")) orelse 0;

    const poly_val = obj.get("polygon") orelse return;
    const poly = switch (poly_val) {
        .array => |arr| arr.items,
        else => return,
    };
    if (poly.len < 2) return;

    const first = readPoint(poly[0]) orelse return;
    var prev = first;
    var use_entity = true;
    for (poly[1..]) |point_val| {
        const next = readPoint(point_val) orelse continue;
        const e = if (use_entity) entity else world.reserveEntity();
        use_entity = false;
        try cb.spawnBundle(e, LineBundle, .{
            .line = .{
                .x0 = base_x + prev.x,
                .y0 = base_y + prev.y,
                .x1 = base_x + next.x,
                .y1 = base_y + next.y,
            },
        });
        prev = next;
    }
    const e = if (use_entity) entity else world.reserveEntity();
    try cb.spawnBundle(e, LineBundle, .{
        .line = .{
            .x0 = base_x + prev.x,
            .y0 = base_y + prev.y,
            .x1 = base_x + first.x,
            .y1 = base_y + first.y,
        },
    });
}

fn readPoint(value: json.Value) ?Point {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    const x = valueToF32(obj.get("x")) orelse return null;
    const y = valueToF32(obj.get("y")) orelse return null;
    return .{ .x = x, .y = y };
}

fn valueToF32(value_opt: ?json.Value) ?f32 {
    const value = value_opt orelse return null;
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => null,
    };
}

const Bundle = struct {
    pos: comps.Position,
    wh: comps.WidthHeight,
    tex: comps.Texture,
};

const LineBundle = struct {
    line: comps.Line,
};

const Point = struct {
    x: f32,
    y: f32,
};

const std = @import("std");
const mem = std.mem;
const json = std.json;

const engine = @import("engine");
const core = engine.core;

const ecs = engine.ecs;

const comps = @import("../components.zig");
