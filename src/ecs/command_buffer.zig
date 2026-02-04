const CommandBuffer = struct {
    commands: CommandList,
    bytes: Buffer,
    gpa: mem.Allocator,

    const Self = @This();

    const CommandList = std.ArrayList(Command);
    const Buffer = std.ArrayList(u8);

    const Tag = enum {
        spawn,
        despawn,
        assign,
        unassign,
    };

    const Command = struct {
        tag: Tag,
        entity: Entity,
        meta: ?*const Archetype.StaticMeta,
        offset: usize,
        size: usize,
    };

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .commands = try CommandList.initCapacity(gpa, 1),
            .bytes = try Buffer.initCapacity(gpa, 16),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.commands.deinit(self.gpa);
        self.bytes.deinit(self.gpa);
    }

    pub fn spawn(self: *Self, entity: Entity, comptime Bundle: type, components: Bundle) !void {
        comptime if (!util.isBundle(Bundle)) @compileError("expected Bundle as argument");

        const types = util.typesOfBundle(Bundle);
        const meta: Archetype.StaticMeta = comptime .from(types);

        var out: [meta.size()]u8 = undefined;
        meta.extractBytes(Bundle, &components, out[0..]);

        const before_size = self.bytes.items.len;
        const payload_size = out.len;
        try self.bytes.appendSlice(self.gpa, out[0..]);
        errdefer self.bytes.items.len = before_size;

        try self.commands.append(self.gpa, Command{
            .tag = .spawn,
            .entity = entity,
            .meta = &meta,
            .offset = before_size,
            .size = payload_size,
        });
    }

    pub fn despawn(self: *Self, entity: Entity) !void {
        try self.commands.append(self.gpa, Command{
            .tag = .despawn,
            .entity = entity,
            .meta = null,
            .offset = undefined,
            .size = undefined,
        });
    }

    pub fn assign(self: *Self, entity: Entity, comptime Bundle: type, components: Bundle) !void {
        comptime if (!util.isBundle(Bundle)) @compileError("expected Bundle as argument");

        const types = util.typesOfBundle(Bundle);
        const meta: Archetype.StaticMeta = comptime .from(types);

        var out: [meta.size()]u8 = undefined;
        meta.extractBytes(Bundle, &components, out[0..]);

        const before_size = self.bytes.items.len;
        const payload_size = out.len;
        try self.bytes.appendSlice(self.gpa, out[0..]);
        errdefer self.bytes.items.len = before_size;

        try self.commands.append(self.gpa, Command{
            .tag = .assign,
            .entity = entity,
            .meta = &meta,
            .offset = before_size,
            .size = payload_size,
        });
    }

    pub fn unassign(self: *Self, entity: Entity, comptime Bundle: type) !void {
        comptime if (!util.isBundle(Bundle)) @compileError("expected Bundle as argument");

        const types = util.typesOfBundle(Bundle);
        const meta: Archetype.StaticMeta = comptime .from(types);
        const offset = self.bytes.items.len;

        try self.commands.append(self.gpa, Command{
            .tag = .unassign,
            .entity = entity,
            .meta = &meta,
            .offset = offset,
            .size = 0,
        });
    }

    pub fn flush(self: *Self, world_ref: *World) !void {
        for (self.commands.items) |cmd| {
            switch (cmd.tag) {
                .spawn => {
                    const meta = cmd.meta.?;
                    const bytes = self.bytes.items[cmd.offset .. cmd.offset + cmd.size];
                    try world_ref.spawnBytes(cmd.entity, meta, bytes);
                },
                .despawn => {
                    _ = world_ref.despawn(cmd.entity);
                },
                .assign => {
                    const meta = cmd.meta.?;
                    const bytes = self.bytes.items[cmd.offset .. cmd.offset + cmd.size];
                    try world_ref.assignBytes(cmd.entity, meta, bytes);
                },
                .unassign => {
                    const meta = cmd.meta.?;
                    try world_ref.unassignMeta(cmd.entity, meta);
                },
            }
        }

        self.commands.clearRetainingCapacity();
        self.bytes.clearRetainingCapacity();
    }
};

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const util = @import("util.zig");
const archetype = @import("archetype.zig");
const world = @import("world.zig");

const Archetype = archetype.Archetype;
const Entity = archetype.Entity;
const World = world.World;

test "CommandBuffer.spawn stores bytes and command" {
    const alloc = testing.allocator;
    var buffer = try CommandBuffer.init(alloc);
    defer buffer.deinit();

    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u16,
    };
    const Velocity = struct {
        pub const cid = 2;
        dx: u8,
        dy: u32,
    };
    const Bundle = struct {
        vel: Velocity,
        pos: Position,
    };

    const bundle = Bundle{
        .vel = .{ .dx = 0x77, .dy = 0x8899AABB },
        .pos = .{ .x = 0x11223344, .y = 0x5566 },
    };

    try buffer.spawn(@as(Entity, 1), Bundle, bundle);

    try testing.expectEqual(@as(usize, 1), buffer.commands.items.len);
    const cmd = buffer.commands.items[0];
    try testing.expectEqual(.spawn, cmd.tag);
    try testing.expectEqual(@as(Entity, 1), cmd.entity);
    try testing.expect(cmd.meta != null);

    const meta = cmd.meta.?;
    const expected = try alloc.alloc(u8, meta.size());
    defer alloc.free(expected);
    meta.extractBytes(Bundle, &bundle, expected);

    try testing.expectEqual(meta.size(), cmd.size);
    try testing.expectEqual(cmd.size, buffer.bytes.items.len);
    try testing.expectEqualSlices(u8, expected, buffer.bytes.items);
}

test "CommandBuffer.despawn stores command" {
    const alloc = testing.allocator;
    var buffer = try CommandBuffer.init(alloc);
    defer buffer.deinit();

    try buffer.despawn(@as(Entity, 5));

    try testing.expectEqual(@as(usize, 1), buffer.commands.items.len);
    const cmd = buffer.commands.items[0];
    try testing.expectEqual(CommandBuffer.Tag.despawn, cmd.tag);
    try testing.expectEqual(@as(Entity, 5), cmd.entity);
    try testing.expect(cmd.meta == null);
}

test "CommandBuffer.assign stores bytes and command" {
    const alloc = testing.allocator;
    var buffer = try CommandBuffer.init(alloc);
    defer buffer.deinit();

    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u16,
    };
    const Velocity = struct {
        pub const cid = 2;
        dx: u8,
        dy: u32,
    };
    const Bundle = struct {
        vel: Velocity,
        pos: Position,
    };

    const bundle = Bundle{
        .vel = .{ .dx = 0x77, .dy = 0x8899AABB },
        .pos = .{ .x = 0x11223344, .y = 0x5566 },
    };

    try buffer.assign(@as(Entity, 3), Bundle, bundle);

    try testing.expectEqual(@as(usize, 1), buffer.commands.items.len);
    const cmd = buffer.commands.items[0];
    try testing.expectEqual(.assign, cmd.tag);
    try testing.expectEqual(@as(Entity, 3), cmd.entity);
    try testing.expect(cmd.meta != null);

    const meta = cmd.meta.?;
    const expected = try alloc.alloc(u8, meta.size());
    defer alloc.free(expected);
    meta.extractBytes(Bundle, &bundle, expected);

    try testing.expectEqual(meta.size(), cmd.size);
    try testing.expectEqual(cmd.size, buffer.bytes.items.len);
    try testing.expectEqualSlices(u8, expected, buffer.bytes.items);
}

test "CommandBuffer.unassign stores command" {
    const alloc = testing.allocator;
    var buffer = try CommandBuffer.init(alloc);
    defer buffer.deinit();

    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u16,
    };
    const Bundle = struct {
        pos: Position,
    };

    try buffer.unassign(@as(Entity, 9), Bundle);

    try testing.expectEqual(@as(usize, 1), buffer.commands.items.len);
    const cmd = buffer.commands.items[0];
    try testing.expectEqual(CommandBuffer.Tag.unassign, cmd.tag);
    try testing.expectEqual(@as(Entity, 9), cmd.entity);
    try testing.expect(cmd.meta != null);
    try testing.expectEqual(@as(usize, 0), cmd.size);
    try testing.expectEqual(@as(usize, 0), buffer.bytes.items.len);
}

test "CommandBuffer.flush applies to World" {
    const alloc = testing.allocator;
    var buffer = try CommandBuffer.init(alloc);
    defer buffer.deinit();

    var w = try World.init(alloc);
    defer w.deinit();

    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u16,
    };
    const Velocity = struct {
        pub const cid = 2;
        dx: u8,
        dy: u32,
    };
    const P = struct { pos: Position };
    const V = struct { vel: Velocity };

    const e = w.reserveEntity();
    try buffer.spawn(e, P, .{ .pos = .{ .x = 7, .y = 9 } });
    try buffer.flush(&w);

    const pos_view = w.getAuto(Position, e).?;
    try testing.expectEqual(@as(u32, 7), pos_view.x.*);
    try testing.expectEqual(@as(u16, 9), pos_view.y.*);
    {
        const arch = w.archetypeOf(e).?;
        try testing.expect(!arch.meta.hasComponents(&[_]type{Velocity}));
    }

    try buffer.assign(e, V, .{ .vel = .{ .dx = 3, .dy = 11 } });
    try buffer.flush(&w);

    const vel_view = w.getAuto(Velocity, e).?;
    try testing.expectEqual(@as(u8, 3), vel_view.dx.*);
    try testing.expectEqual(@as(u32, 11), vel_view.dy.*);

    try buffer.unassign(e, P);
    try buffer.flush(&w);
    {
        const arch = w.archetypeOf(e).?;
        try testing.expect(!arch.meta.hasComponents(&[_]type{Position}));
        try testing.expect(arch.meta.hasComponents(&[_]type{Velocity}));
    }

    try buffer.despawn(e);
    try buffer.flush(&w);
    try testing.expectEqual(@as(usize, 0), w.count());
}
