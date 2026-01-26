pub const Entity = u32;

pub const World = struct {
    next_entity: Entity,
    gpa: mem.Allocator,
    archetypes: ArchetypeHashMap,
    entity_archetype: EntityArchetypeHashMap,

    const Self = @This();
    const ArchetypeHashMap = std.AutoHashMap(u64, Archetype);
    const EntityArchetypeHashMap = std.AutoArrayHashMap(Entity, u64);

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .next_entity = 0,
            .archetypes = ArchetypeHashMap.init(gpa),
            .entity_archetype = EntityArchetypeHashMap.init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.archetypes.valueIterator();
        while (it.next()) |arch|
            arch.deinit(self.gpa);
        self.archetypes.deinit();
        self.entity_archetype.deinit();
    }

    pub fn spawn(self: *Self, comptime components: anytype) !Entity {
        comptime {
            if (!util.isTuple(components))
                @compileError("expected tuple as argument");
        }

        const types = util.typesOfTuple(components);
        var arch = try self.getOrCreateArchetype(.from(types));
        try arch.append(self.gpa, components);

        const e = self.next_entity;
        try self.entity_archetype.put(e, arch.hash);

        self.next_entity += 1;

        return e;
    }

    fn getOrCreateArchetype(self: *Self, meta: Archetype.Meta) !Archetype {
        const hash = meta.hash();
        if (self.archetypes.get(hash)) |arch| return arch;
        const arch = try Archetype.init(self.gpa, meta);
        try self.archetypes.put(arch.hash, arch);
        return arch;
    }

    pub fn query(self: *Self, comptime Comps: []const type) QueryIterator {
        const cids = comptime blk: {
            // generate a static array of cids
            var tmp: [Comps.len]u32 = undefined;
            for (Comps, 0..) |C, i| {
                if (!@hasDecl(C, "cid"))
                    @compileError("Comps should be component");
                tmp[i] = C.cid;
            }
            break :blk tmp;
        };
        return self.queryCIDs(cids[0..]);
    }

    pub fn queryCIDs(self: *Self, cids: []const u32) QueryIterator {
        return .{
            .cids = cids,
            .arch_iter = self.archetypes.valueIterator(),
            .current_iter = null,
        };
    }

    pub const QueryIterator = struct {
        cids: []const u32, // TODO: cids are runtime and dynamic: consider compile time cids
        arch_iter: ArchetypeHashMap.ValueIterator,
        current_iter: ?Archetype.Iterator,

        pub fn next(self: *QueryIterator) bool {
            while (true) {
                if (self.current_iter) |*arch_it| {
                    if (arch_it.next()) return true;
                }
                const next_arch = while (true) {
                    if (self.arch_iter.next()) |arch| {
                        if (arch.meta.hasCIDs(self.cids))
                            break arch;
                    } else {
                        return false;
                    }
                };
                self.current_iter = next_arch.iter();
            }
        }

        pub fn get(self: *const QueryIterator, comptime View: type) View {
            const view_ti = @typeInfo(View);
            if (view_ti != .@"struct")
                @compileError("View should be a struct");
            if (!@hasDecl(View, "Of"))
                @compileError("View should declare 'Of'");
            const Of = View.Of;
            const comp_ti = @typeInfo(Of);
            if (comp_ti != .@"struct")
                @compileError("View.Of should be a struct");
            if (!@hasDecl(Of, "cid"))
                @compileError("View.Of is not component");

            const found = for (self.cids) |cid| {
                if (cid == Of.cid) break true;
            } else false;
            assert(found);

            return self.current_iter.?.get(View);
        }

        pub fn getAuto(self: *const QueryIterator, comptime T: type) util.ViewOf(T) {
            const ti = @typeInfo(T);
            if (ti != .@"struct")
                @compileError("View.Of should be a struct");
            if (!@hasDecl(T, "cid"))
                @compileError("View.Of is not component");

            const found = for (self.cids) |cid| {
                if (cid == T.cid) break true;
            } else false;
            assert(found);

            return self.current_iter.?.getAuto(T);
        }
    };
};

test "World.spawn" {
    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const Velocity = struct {
        pub const cid = 2;
        x: u32,
        y: u32,
    };

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    _ = try world.spawn(.{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 1 },
    });
    _ = try world.spawn(.{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 1 },
    });

    var it = world.archetypes.valueIterator();
    var arch = it.next() orelse unreachable;
    try testing.expectEqual(2, arch.len());
    try testing.expectEqual(null, it.next());
}

test "World.QueryIterator" {
    const Flag = struct {
        pub const cid = 0;
        value: u8,
    };
    const Position = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const PositionView = struct {
        pub const Of = Position;
        x: *u32,
        y: *u32,
    };
    const Velocity = struct {
        pub const cid = 2;
        x: u32,
        y: u32,
    };

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    _ = try world.spawn(.{
        Flag{ .value = 0 },
        Position{ .x = 0, .y = 0 },
    });
    _ = try world.spawn(.{
        Flag{ .value = 1 },
        Position{ .x = 50, .y = 50 },
        Velocity{ .x = 100, .y = 100 },
    });

    var it = world.query(&[_]type{ Position, Flag });
    var count: usize = 0;
    while (it.next()) {
        count += 1;
        switch (it.getAuto(Flag).value.*) {
            0 => {
                const p = it.get(PositionView);
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            },
            1 => {
                const p = it.get(PositionView);
                try testing.expectEqual(50, p.x.*);
                try testing.expectEqual(50, p.y.*);
            },
            else => unreachable,
        }
    }
    try testing.expectEqual(2, count);
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const util = @import("util.zig");
const Archetype = @import("archetype.zig").Archetype;
