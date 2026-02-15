pub const LevelPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;

        _ = try app.insertResource(resources.RoomManager, .init(app.gpa));

        const registry = app.getResource(prefabs.Registry).?;
        try registry.register("map", PrefabsFactory.mapFactory);
        try registry.register("spawn_point", PrefabsFactory.spawnPointFactory);
        try registry.register("door", PrefabsFactory.doorFactory);
        try registry.register("layer", PrefabsFactory.layerFactory);
        try registry.register("edge", PrefabsFactory.edgeFactory);

        try app.addSystem(.startup, LevelSystem);
        try app.addSystem(.fixed_update, DoorSystem);
    }
};

const LevelSystem = struct {
    pub const provides: []const []const u8 = &.{"level"};
    pub fn run(app: *core.App) !void {
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;
        const room_mgr = app.getResource(resources.RoomManager).?;
        const registry = app.getResource(prefabs.Registry).?;

        if (assets_mgr.configValuePath("levels", &.{"spawn"})) |spawn| {
            const spawn_own = try room_mgr.own(spawn.string);
            room_mgr.current = comps.Room.init(spawn_own).id;
        }

        const rooms = assets_mgr.configValuePath("levels", &.{"rooms"}).?;
        var it = rooms.object.iterator();
        while (it.next()) |lvl_entry| {
            const room_own = try room_mgr.own(lvl_entry.key_ptr.*);
            var parsed = try prefabs.Registry.loadTiledJson(
                std.heap.page_allocator,
                lvl_entry.value_ptr.*.string,
            );
            defer parsed.deinit();
            try registry.spawnFromTiledValue(app, parsed.value, room_own);
        }
    }
};

const DoorSystem = struct {
    pub const provides: []const []const u8 = &.{"teleport"};
    pub const after_all_labels: []const []const u8 = &.{"physics"};

    pub fn run(app: *core.App) !void {
        const room_mgr = app.getResource(resources.RoomManager).?;

        var it = app.world.query(&[_]type{
            comps.Player,
            comps.Position,
            comps.Room,
        });
        while (it.next()) |_| {
            const player = it.get(comps.PlayerView);
            const pos = it.get(comps.PositionView);
            const room = it.get(comps.RoomView);

            var it_door = app.world.query(&[_]type{
                comps.Teleport,
                comps.Position,
                comps.ColliderCircle,
                comps.Room,
            });
            it_door = it_door;
            while (it_door.next()) |_| {
                const tp = it_door.get(comps.TeleportView);
                const tp_pos = it_door.get(comps.PositionView);
                const tp_col = it_door.get(comps.ColliderCircleView);
                const tp_room = it_door.get(comps.RoomView);

                if (room.id.* != tp_room.id.*) continue;

                if (rl.CheckCollisionPointCircle(
                    .{ .x = pos.x.*, .y = pos.y.* },
                    .{ .x = tp_pos.x.*, .y = tp_pos.y.* },
                    tp_col.radius.*,
                )) {
                    room.id.* = tp.room_id.*;
                    room_mgr.current = room.id.*;
                    player.just_spawned.* = true;
                    break;
                }
            }
        }
    }
};

const PrefabsFactory = struct {
    fn mapFactory(
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
            try room_mgr.setBounds(comps.Room.init(room_ref).id, bounds);
        }
    }

    fn spawnPointFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const room_mgr = app.getResource(resources.RoomManager).?;
        const room_name = try room_mgr.own(room_ref);

        const x = valueToF32(object.object.get("x")).?;
        const y = valueToF32(object.object.get("y")).?;

        const e = app.world.reserveEntity();
        try cb.spawnBundle(e, SpawnPointBundle, .{
            .spawn = .{},
            .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
            .room = .init(room_name),
        });
    }

    fn doorFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const room_mgr = app.getResource(resources.RoomManager).?;
        const room_name = try room_mgr.own(room_ref);

        const tp_room = valueToStr(object.object.get("name")).?;
        const x = valueToF32(object.object.get("x")).?;
        const y = valueToF32(object.object.get("y")).?;
        const r = valueToF32(object.object.get("width")).? / 2.0;

        const e = app.world.reserveEntity();
        try cb.spawnBundle(e, DoorBundle, .{
            .tp = .{ .room_id = comps.Room.init(tp_room).id },
            .pos = .{ .x = x, .y = y, .prev_x = x, .prev_y = y },
            .col = .{ .radius = r, .mask = 1 << 2 },
            .room = .init(room_name),
        });
    }

    fn layerFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const room_mgr = app.getResource(resources.RoomManager).?;
        const room_name = try room_mgr.own(room_ref);

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
            .tex = .{ .name = owned_key, .z_index = z_index },
            .room = .init(room_name),
        });
    }

    fn edgeFactory(
        gpa: mem.Allocator,
        app: *core.App,
        cb: *ecs.CommandBuffer,
        object: json.Value,
        room_ref: []const u8,
    ) !void {
        _ = gpa;

        const room_mgr = app.getResource(resources.RoomManager).?;
        const room_name = try room_mgr.own(room_ref);

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
                .room = .init(room_name),
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
            .room = .init(room_name),
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
    tp: comps.Teleport,
    pos: comps.Position,
    col: comps.ColliderCircle,
    room: comps.Room,
};

const SpawnPointBundle = struct {
    spawn: comps.SpawnPoint,
    pos: comps.Position,
    room: comps.Room,
};

const LayerBundle = struct {
    pos: comps.Position,
    wh: comps.WidthHeight,
    tex: comps.Texture,
    room: comps.Room,
};

const LineBundle = struct {
    line: comps.ColliderLine,
    room: comps.Room,
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
const rl = engine.rl;

const comps = @import("../components.zig");
const resources = @import("../resources.zig");
