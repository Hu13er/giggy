pub const PrefabsFactory = struct {
    pub fn mapFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;
        _ = cb;
        var room_mgr = app.getResource(resources.RoomManager).?;
        if (readRoomBounds(object)) |bounds| {
            try room_mgr.setBounds(resources.roomIdFromName(room_ref), bounds);
        }
    }

    pub fn spawnPointFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const x = valueToF32(object.object.get("x")).?;
        const y = valueToF32(object.object.get("y")).?;
        const spawn_id: u8 = readSpawnId(object) orelse 0;

        const e = app.world.reserveEntity();
        try cb.spawnBundle(e, SpawnPointBundle, .{
            .spawn = .{ .id = spawn_id },
            .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
            .room = resources.roomFromName(room_ref),
        });
    }

    pub fn doorFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const tp_room = valueToStr(object.object.get("name")).?;
        const x = valueToF32(object.object.get("x")).?;
        const y = valueToF32(object.object.get("y")).?;
        const r = valueToF32(object.object.get("width")).? / 2.0;
        const spawn_id: u8 = readSpawnIdPropertyOnly(object) orelse 0;

        const e = app.world.reserveEntity();
        try cb.spawnBundle(e, DoorBundle, .{
            .tp = .{ .room_id = resources.roomIdFromName(tp_room), .spawn_id = spawn_id },
            // Tiled rectangle objects use (x,y) as top-left; we store position as circle center.
            .pos = .{ .x = x + r, .y = y + r, .prev_x = x + r, .prev_y = y + r },
            .col = .{ .radius = r, .mask = 0 },
            .room = resources.roomFromName(room_ref),
        });
    }

    pub fn layerFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const obj = switch (object) {
            .object => |o| o,
            else => return,
        };

        const name = valueToStr(obj.get("name")) orelse return;
        const base_x = valueToF32(obj.get("x")) orelse 0;
        const base_y = valueToF32(obj.get("y")) orelse 0;
        const offset_x = valueToF32(obj.get("offsetx")) orelse 0;
        const offset_y = valueToF32(obj.get("offsety")) orelse 0;
        const x = base_x + offset_x;
        const y = base_y + offset_y;
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

        const entity = app.world.reserveEntity();
        try cb.spawnBundle(entity, LayerBundle, .{
            .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
            .wh = .{ .w = w, .h = h },
            .tex = .{ .name = owned_key },
            .z_index = .{ .value = z_index },
            .room = resources.roomFromName(room_ref),
        });
    }

    pub fn edgeFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
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
        const base_entity = app.world.reserveEntity();
        var use_entity = true;
        for (poly[1..]) |point_val| {
            const next = readPoint(point_val) orelse continue;
            const e = if (use_entity) base_entity else app.world.reserveEntity();
            use_entity = false;
            try cb.spawnBundle(e, LineBundle, .{
                .line = .{
                    .x0 = base_x + prev.x,
                    .y0 = base_y + prev.y,
                    .x1 = base_x + next.x,
                    .y1 = base_y + next.y,
                    .mask = 1,
                },
                .room = resources.roomFromName(room_ref),
            });
            prev = next;
        }
        const e = if (use_entity) base_entity else app.world.reserveEntity();
        try cb.spawnBundle(e, LineBundle, .{
            .line = .{
                .x0 = base_x + prev.x,
                .y0 = base_y + prev.y,
                .x1 = base_x + first.x,
                .y1 = base_y + first.y,
                .mask = 1,
            },
            .room = resources.roomFromName(room_ref),
        });
    }
};

fn readRoom(map: json.Value) ?[]const u8 {
    const obj = switch (map) {
        .object => |o| o,
        else => return null,
    };
    const layers_val = obj.get("layers") orelse return null;
    const layers = switch (layers_val) {
        .array => |arr| arr,
        else => return null,
    };
    for (layers.items) |layer| {
        const layer_obj = switch (layer) {
            .object => |o| o,
            else => continue,
        };
        const class = valueToStr(layer_obj.get("class")) orelse continue;
        if (!std.mem.eql(u8, "room", class)) continue;
        const name = valueToStr(layer_obj.get("name")) orelse continue;
        return name;
    }
    return null;
}

fn readRoomBounds(map: json.Value) ?resources.RoomBounds {
    const obj = switch (map) {
        .object => |o| o,
        else => return null,
    };
    const layers_val = obj.get("layers") orelse return null;
    const layers = switch (layers_val) {
        .array => |arr| arr,
        else => return null,
    };
    for (layers.items) |layer| {
        const layer_obj = switch (layer) {
            .object => |o| o,
            else => continue,
        };
        const layer_type = valueToStr(layer_obj.get("type")) orelse "";
        if (!std.mem.eql(u8, layer_type, "imagelayer")) continue;

        const class = valueToStr(layer_obj.get("class")) orelse "";
        const name = valueToStr(layer_obj.get("name")) orelse "";
        const is_map_class = std.mem.eql(u8, class, "map");
        const is_map_name = std.mem.endsWith(u8, name, "/map") or std.mem.eql(u8, name, "map");
        const has_bounds_prop = valueHasBoolProperty(layer_obj.get("properties"), "bounds", true);
        if (!is_map_class and !is_map_name and !has_bounds_prop) continue;

        const w = valueToF32(layer_obj.get("imagewidth")) orelse continue;
        const h = valueToF32(layer_obj.get("imageheight")) orelse continue;
        const base_x = valueToF32(layer_obj.get("x")) orelse 0;
        const base_y = valueToF32(layer_obj.get("y")) orelse 0;
        const offset_x = valueToF32(layer_obj.get("offsetx")) orelse 0;
        const offset_y = valueToF32(layer_obj.get("offsety")) orelse 0;
        const x = base_x + offset_x;
        const y = base_y + offset_y;

        return .{ .x = x, .y = y, .w = w, .h = h };
    }
    return null;
}

fn valueHasBoolProperty(props_opt: ?json.Value, name: []const u8, expected: bool) bool {
    const props = props_opt orelse return false;
    const props_arr = switch (props) {
        .array => |arr| arr,
        else => return false,
    };
    for (props_arr.items) |props_item| {
        const item_obj = switch (props_item) {
            .object => |o| o,
            else => continue,
        };
        const item_name = valueToStr(item_obj.get("name")) orelse continue;
        if (!std.mem.eql(u8, item_name, name)) continue;
        const value = item_obj.get("value") orelse return false;
        return switch (value) {
            .bool => |b| b == expected,
            else => false,
        };
    }
    return false;
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

fn readSpawnId(object: json.Value) ?u8 {
    const obj = switch (object) {
        .object => |o| o,
        else => return null,
    };

    if (valueIntProperty(obj.get("properties"), "spawn_id")) |id_i64| {
        if (id_i64 < 0 or id_i64 > std.math.maxInt(u8)) return null;
        return @intCast(id_i64);
    }

    const name = valueToStr(obj.get("name")) orelse return null;
    return parseTrailingU8(name);
}

fn readSpawnIdPropertyOnly(object: json.Value) ?u8 {
    const obj = switch (object) {
        .object => |o| o,
        else => return null,
    };
    const id_i64 = valueIntProperty(obj.get("properties"), "spawn_id") orelse return null;
    if (id_i64 < 0 or id_i64 > std.math.maxInt(u8)) return null;
    return @intCast(id_i64);
}

fn valueIntProperty(props_opt: ?json.Value, name: []const u8) ?i64 {
    const props = props_opt orelse return null;
    const props_arr = switch (props) {
        .array => |arr| arr,
        else => return null,
    };
    for (props_arr.items) |props_item| {
        const item_obj = switch (props_item) {
            .object => |o| o,
            else => continue,
        };
        const item_name = valueToStr(item_obj.get("name")) orelse continue;
        if (!std.mem.eql(u8, item_name, name)) continue;
        const value = item_obj.get("value") orelse return null;
        return switch (value) {
            .integer => |i| i,
            else => null,
        };
    }
    return null;
}

fn parseTrailingU8(s: []const u8) ?u8 {
    var end: usize = s.len;
    while (end > 0 and std.ascii.isDigit(s[end - 1])) : (end -= 1) {}
    if (end == s.len) return null;

    const digits = s[end..];
    return std.fmt.parseInt(u8, digits, 10) catch null;
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

fn valueToU16(value_opt: ?json.Value) ?u16 {
    const value = value_opt orelse return null;
    return switch (value) {
        .integer => |i| @intCast(i),
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

const DoorBundle = struct {
    tp: components.world.Teleport,
    pos: components.transform.Position,
    col: components.collision.ColliderCircle,
    room: components.world.Room,
};

const SpawnPointBundle = struct {
    spawn: components.world.SpawnPoint,
    pos: components.transform.Position,
    room: components.world.Room,
};

const LayerBundle = struct {
    pos: components.transform.Position,
    wh: components.render.WidthHeight,
    tex: components.render.Texture,
    z_index: components.render.ZIndex,
    room: components.world.Room,
};

const LineBundle = struct {
    line: components.collision.ColliderLine,
    room: components.world.Room,
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
const ecs = engine.ecs;

const game = @import("game");
const components = game.components;
const resources = game.plugins.level.resources;
