pub const LevelPlugin = struct {
    file_path: []const u8,

    pub fn build(self: @This(), app: *core.App) !void {
        _ = try app.insertResource(resources.Level, .{ .file_path = self.file_path });

        const registry = app.getResource(prefabs.Registry).?;
        try registry.register("layer", PrefabsFactory.layerFactory);
        try registry.register("edge", PrefabsFactory.edgeFactory);

        try app.addSystem(.startup, LevelSystem);
    }
};

const LevelSystem = struct {
    pub const provides: []const []const u8 = &.{"level"};
    pub fn run(app: *core.App) !void {
        const level_resc = app.getResource(resources.Level).?;
        const registry = app.getResource(prefabs.Registry).?;
        try registry.spawnFromTiledFile(app, std.heap.page_allocator, level_resc.file_path);
    }
};

const PrefabsFactory = struct {
    fn layerFactory(gpa: mem.Allocator, app: *core.App, cb: *ecs.CommandBuffer, entity: ecs.Entity, object: json.Value) !void {
        _ = gpa;

        const obj = switch (object) {
            .object => |o| o,
            else => return,
        };

        const name = valueToStr(obj.get("name")) orelse return;
        const x = valueToF32(obj.get("offsetx")) orelse return;
        const y = valueToF32(obj.get("offsety")) orelse return;
        const w = valueToF32(obj.get("imagewidth")) orelse return;
        const h = valueToF32(obj.get("imageheight")) orelse return;

        var z_index: i16 = 0;
        if (obj.get("properties")) |props| blk: {
            const props_arr = switch (props) {
                .array => |arr| arr,
                else => break :blk,
            };
            for (props_arr.items) |props_item| {
                const item_obj = switch (props_item) {
                    .object => |o| o,
                    else => continue,
                };
                const item_name = valueToStr(item_obj.get("name")) orelse continue;
                if (std.mem.eql(u8, item_name, "z_index")) {
                    z_index = valueToI16(item_obj.get("value")) orelse 0;
                } else {
                    continue;
                }
            }
        }

        const asset_mgr = app.getResource(assets.AssetManager).?;
        const owned_key = asset_mgr.textures.getKey(name) orelse return;

        try cb.spawnBundle(entity, LayerBundle, .{
            .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
            .wh = .{ .w = w, .h = h },
            .tex = .{ .name = owned_key, .z_index = z_index },
        });
    }

    fn edgeFactory(gpa: mem.Allocator, app: *core.App, cb: *ecs.CommandBuffer, entity: ecs.Entity, object: json.Value) !void {
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
            const e = if (use_entity) entity else app.world.reserveEntity();
            use_entity = false;
            try cb.spawnBundle(e, LineBundle, .{
                .line = .{
                    .x0 = base_x + prev.x,
                    .y0 = base_y + prev.y,
                    .x1 = base_x + next.x,
                    .y1 = base_y + next.y,
                    .mask = 1,
                },
            });
            prev = next;
        }
        const e = if (use_entity) entity else app.world.reserveEntity();
        try cb.spawnBundle(e, LineBundle, .{
            .line = .{
                .x0 = base_x + prev.x,
                .y0 = base_y + prev.y,
                .x1 = base_x + first.x,
                .y1 = base_y + first.y,
                .mask = 1,
            },
        });
    }
};

fn readPoint(value: json.Value) ?Point {
    const obj = switch (value) {
        .object => |o| o,
        else => return null,
    };
    const x = valueToF32(obj.get("x")) orelse return null;
    const y = valueToF32(obj.get("y")) orelse return null;
    return .{ .x = x, .y = y };
}

fn valueToStr(value_opt: ?json.Value) ?[]const u8 {
    const value = value_opt orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn valueToF32(value_opt: ?json.Value) ?f32 {
    const value = value_opt orelse return null;
    return switch (value) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => null,
    };
}

fn valueToI16(value_opt: ?json.Value) ?i16 {
    const value = value_opt orelse return null;
    return switch (value) {
        .integer => |i| @intCast(i),
        else => null,
    };
}

const LayerBundle = struct {
    pos: comps.Position,
    wh: comps.WidthHeight,
    tex: comps.Texture,
};

const LineBundle = struct {
    line: comps.ColliderLine,
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
const assets = engine.assets;
const prefabs = engine.prefabs;
const ecs = engine.ecs;

const comps = @import("../components.zig");
const resources = @import("../resources.zig");
