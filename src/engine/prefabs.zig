pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        var registry = Registry.init(app.gpa);
        errdefer registry.deinit();
        _ = try app.insertResource(Registry, registry);
    }
};

pub const Registry = struct {
    factories: std.StringHashMap(PrefabFactory),
    gpa: mem.Allocator,

    const Self = @This();
    pub const PrefabFactory = *const fn (
        gpa: mem.Allocator,
        app: *core.App,
        command_buffer: *CommandBuffer,
        entity: ecs.Entity,
        object: json.Value,
    ) anyerror!void;

    pub const Error = error{
        DuplicatePrefab,
        InvalidTiledJson,
    };

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .gpa = gpa,
            .factories = std.StringHashMap(PrefabFactory).init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.factories.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
        }
        self.factories.deinit();
    }

    pub fn register(self: *Self, key: []const u8, factory: PrefabFactory) (Error || mem.Allocator.Error)!void {
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);

        const gop = try self.factories.getOrPut(key_copy);
        if (gop.found_existing) {
            return Error.DuplicatePrefab;
        }

        gop.key_ptr.* = key_copy;
        gop.value_ptr.* = factory;
    }

    pub fn spawnFromTiledFile(self: *Self, app: *core.App, page_allocator: mem.Allocator, file_path: []const u8) !void {
        var parsed = try loadTiledJson(page_allocator, file_path);
        defer parsed.deinit();
        try self.spawnFromTiledValue(app, parsed.value);
    }

    pub fn spawnFromTiledValue(self: *Self, app: *core.App, map: json.Value) !void {
        var cb = try CommandBuffer.init(self.gpa);
        defer cb.deinit();

        const map_obj = switch (map) {
            .object => |obj| obj,
            else => return Error.InvalidTiledJson,
        };

        const layers_val = map_obj.get("layers") orelse return Error.InvalidTiledJson;
        const layers = switch (layers_val) {
            .array => |arr| arr.items,
            else => return Error.InvalidTiledJson,
        };

        for (layers) |layer_val| {
            const layer_obj = switch (layer_val) {
                .object => |obj| obj,
                else => continue,
            };

            const layer_type = objectFieldString(layer_obj, "type") orelse "";
            if (mem.eql(u8, layer_type, "objectgroup")) {
                const objects_val = layer_obj.get("objects") orelse continue;
                const objects = switch (objects_val) {
                    .array => |arr| arr.items,
                    else => continue,
                };

                for (objects) |object_val| {
                    const object_obj = switch (object_val) {
                        .object => |obj| obj,
                        else => continue,
                    };

                    const prefab_name = resolvePrefabClass(object_obj) orelse continue;
                    const factory = self.factories.get(prefab_name) orelse continue;
                    const e = app.world.reserveEntity();
                    try factory(self.gpa, app, &cb, e, object_val);
                }
            } else if (mem.eql(u8, layer_type, "imagelayer")) {
                const prefab_name = resolvePrefabClass(layer_obj) orelse continue;
                const factory = self.factories.get(prefab_name) orelse continue;
                const e = app.world.reserveEntity();
                try factory(self.gpa, app, &cb, e, layer_val);
            }
        }
        try cb.flush(&app.world);
    }

    pub fn loadTiledJson(allocator: mem.Allocator, file_path: []const u8) !json.Parsed(json.Value) {
        var file = try fs.cwd().openFile(file_path, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, math.maxInt(usize));
        defer allocator.free(contents);

        return try json.parseFromSlice(
            json.Value,
            allocator,
            contents,
            .{ .allocate = .alloc_always },
        );
    }

    fn resolvePrefabClass(object_obj: json.ObjectMap) ?[]const u8 {
        if (objectFieldString(object_obj, "class")) |value| {
            if (value.len > 0) return value;
        }
        if (objectFieldString(object_obj, "type")) |value| {
            if (value.len > 0) return value;
        }
        return null;
    }

    fn objectFieldString(object_obj: json.ObjectMap, key: []const u8) ?[]const u8 {
        const value = object_obj.get(key) orelse return null;
        return switch (value) {
            .string => |s| s,
            else => null,
        };
    }
};

test "Registry.spawnFromTiledValue spawns from object and image layers" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const Spawned = struct {
        kind: u8,
    };
    const Bundle = struct {
        spawned: Spawned,
    };

    const funcs = struct {
        fn boxFactory(entity: ecs.Entity, world: *ecs.World, cb: *CommandBuffer, gpa: mem.Allocator, object: json.Value) !void {
            _ = world;
            _ = gpa;
            _ = object;
            try cb.spawnBundle(entity, Bundle, .{ .spawned = .{ .kind = 1 } });
        }

        fn skyFactory(entity: ecs.Entity, world: *ecs.World, cb: *CommandBuffer, gpa: mem.Allocator, object: json.Value) !void {
            _ = world;
            _ = gpa;
            _ = object;
            try cb.spawnBundle(entity, Bundle, .{ .spawned = .{ .kind = 2 } });
        }
    };

    var registry = Registry.init(alloc);
    defer registry.deinit();
    try registry.register("box", funcs.boxFactory);
    try registry.register("sky", funcs.skyFactory);

    var world = try ecs.World.init(alloc);
    defer world.deinit();

    const source =
        \\{
        \\  "layers": [
        \\    {
        \\      "type": "objectgroup",
        \\      "objects": [
        \\        { "name": "box" }
        \\      ]
        \\    },
        \\    {
        \\      "type": "imagelayer",
        \\      "name": "sky"
        \\    }
        \\  ]
        \\}
    ;

    var parsed = try json.parseFromSlice(json.Value, alloc, source, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    try registry.spawnFromTiledValue(&world, parsed.value);
    try testing.expectEqual(@as(usize, 2), world.count());

    const v0 = world.getAuto(Spawned, @as(ecs.Entity, 0)).?;
    const v1 = world.getAuto(Spawned, @as(ecs.Entity, 1)).?;
    try testing.expectEqual(@as(u8, 1), v0.kind.*);
    try testing.expectEqual(@as(u8, 2), v1.kind.*);
}

const std = @import("std");
const core = @import("core.zig");
const ecs = @import("ecs.zig");
const CommandBuffer = ecs.CommandBuffer;

const json = std.json;
const fs = std.fs;
const mem = std.mem;
const math = std.math;
