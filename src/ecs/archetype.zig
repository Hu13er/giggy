pub const Entity = u32;

pub const Archetype = struct {
    meta: Meta,
    entities: EntityList,
    entities_index: EntityIndexHashmap,
    components: []MultiField,
    hash: u64,

    const Self = @This();
    const EntityList = std.ArrayList(Entity);
    const EntityIndexHashmap = std.AutoHashMap(Entity, usize);

    pub const Meta = struct {
        components: []const MultiField.Meta,

        pub const empty = from(&[_]type{});

        pub inline fn from(comptime Ts: []const type) Meta {
            if (Ts.len == 0)
                return .{ .components = &[0]MultiField.Meta{} };

            var metas: [Ts.len]MultiField.Meta = undefined;
            inline for (Ts, 0..) |T, i| {
                metas[i] = MultiField.Meta.from(T);
            }
            std.sort.insertion(MultiField.Meta, &metas, {}, struct {
                fn lessThan(_: void, a: MultiField.Meta, b: MultiField.Meta) bool {
                    return a.cid < b.cid;
                }
            }.lessThan);
            inline for (1..metas.len) |i| {
                assert(metas[i - 1].cid != metas[i].cid);
            }
            return .{ .components = &metas };
        }

        pub fn clone(self: *const Meta, gpa: mem.Allocator) !Meta {
            var comps = try gpa.alloc(MultiField.Meta, self.components.len);
            for (comps, 0..) |_, i| {
                comps[i] = self.components[i].clone(gpa) catch |err| {
                    for (0..i) |j|
                        comps[j].deinit(gpa);
                    return err;
                };
            }
            return .{ .components = comps };
        }

        pub fn deinit(self: *const Meta, gpa: mem.Allocator) void {
            for (self.components) |comp|
                comp.deinit(gpa);
            gpa.free(self.components);
        }

        pub fn hash(self: *const Meta) u64 {
            var hasher = std.hash.Wyhash.init(0);
            for (self.components) |comp|
                hasher.update(mem.asBytes(&comp.cid));
            return hasher.final();
        }

        pub fn hasComponents(self: *const Meta, comptime Comps: []const type) bool {
            var cids: [Comps.len]u32 = undefined;
            inline for (Comps, 0..) |C, i| {
                if (!@hasDecl(C, "cid"))
                    @compileError("Comps should be component");
                cids[i] = C.cid;
            }
            return self.hasCIDs(cids[0..]);
        }

        pub fn hasCIDs(self: *const Meta, cids: []const u32) bool {
            for (cids) |cid| {
                const found = for (self.components) |comp| {
                    if (comp.cid == cid) break true;
                } else false;
                if (!found) return false;
            }
            return true;
        }
    };

    pub const Iterator = struct {
        archetype: *Self,
        next_index: usize,

        pub fn next(self: *Iterator) ?Entity {
            if (self.next_index >= self.archetype.len())
                return null;
            self.next_index += 1;
            return self.archetype.entities.items[self.next_index - 1];
        }

        pub fn get(self: *const Iterator, comptime View: type) View {
            assert(self.next_index > 0);
            return self.archetype.at(View, self.next_index - 1);
        }

        pub fn getAuto(self: *const Iterator, comptime C: type) util.ViewOf(C) {
            assert(self.next_index > 0);
            return self.archetype.atAuto(C, self.next_index - 1);
        }
    };

    pub fn iter(self: *Self) Iterator {
        return .{
            .archetype = self,
            .next_index = 0,
        };
    }

    pub fn init(gpa: mem.Allocator, meta: Meta) !Self {
        var comps = try gpa.alloc(MultiField, meta.components.len);
        errdefer gpa.free(comps);

        for (meta.components, 0..) |cm, i| {
            comps[i] = MultiField.init(gpa, cm) catch |err| {
                for (0..i) |j|
                    comps[j].deinit(gpa);
                return err;
            };
        }

        return .{
            .meta = try meta.clone(gpa),
            .entities = try EntityList.initCapacity(gpa, 1),
            .entities_index = EntityIndexHashmap.init(gpa),
            .components = comps,
            .hash = meta.hash(),
        };
    }

    pub fn deinit(self: *Self, gpa: mem.Allocator) void {
        if (self.meta.components.len > 0) {
            for (self.components) |comp|
                comp.deinit(gpa);
        }
        gpa.free(self.components);
        self.entities.deinit(gpa);
        self.entities_index.deinit();
        self.meta.deinit(gpa);
    }

    pub fn append(self: *Self, gpa: mem.Allocator, entity: Entity, component_list: anytype) !void {
        const ti = @typeInfo(@TypeOf(component_list));
        assert(ti == .@"struct");

        const fields = ti.@"struct".fields;
        assert(fields.len == self.components.len);

        var cid_indexes: [fields.len]usize = undefined;
        inline for (fields, 0..) |f, i| {
            const T = f.type;
            assert(@hasDecl(T, "cid"));
            cid_indexes[i] = self.indexOfCID(T.cid) orelse unreachable;
        }

        // check for duplication
        for (fields, 0..) |_, i| {
            for (0..i) |j| if (cid_indexes[i] == cid_indexes[j]) unreachable;
        }

        try self.entities_index.put(entity, self.len());
        errdefer _ = self.entities_index.remove(entity);
        try self.entities.append(gpa, entity);
        errdefer _ = self.entities.pop();
        inline for (fields, cid_indexes, 0..) |f, cid_idx, i| {
            const value = @field(component_list, f.name);
            self.components[cid_idx].append(gpa, value) catch |err| {
                for (0..i) |j|
                    self.components[cid_indexes[j]].pop();
                return err;
            };
        }
    }

    pub fn appendRaw(self: *Self, gpa: mem.Allocator, entity: Entity, data: []const []const []const u8) !void {
        assert(data.len == self.components.len);
        try self.entities_index.put(entity, self.len());
        errdefer self.entities_index.remove(entity);
        try self.entities.append(gpa, entity);
        errdefer _ = self.entities.pop();
        for (self.components, data, 0..) |*c, d, i| {
            c.appendRaw(gpa, d) catch |err| {
                for (0..i) |j|
                    self.components[j].pop();
                return err;
            };
        }
    }

    pub fn remove(self: *Self, index: usize) Entity {
        assert(index < self.len());
        const entity = self.entities.swapRemove(index);
        _ = self.entities_index.remove(entity);
        for (self.components) |comp|
            comp.remove(index);
        return entity;
    }

    pub fn pop(self: *Self) Entity {
        return self.remove(self.len() - 1);
    }

    pub fn indexOf(self: *const Self, entity: Entity) ?usize {
        return self.entities_index.get(entity);
    }

    pub fn at(self: *const Self, comptime View: type, index: usize) View {
        assert(0 <= index and index < self.len());

        const view_ti = @typeInfo(View);
        if (view_ti != .@"struct")
            @compileError("View should be a struct");
        const view_fields = view_ti.@"struct".fields;

        if (!@hasDecl(View, "Of"))
            @compileError("View should declare 'Of'");
        const Of = View.Of;
        const comp_ti = @typeInfo(Of);
        if (comp_ti != .@"struct")
            @compileError("View.Of should be a struct");
        const comp_fields = comp_ti.@"struct".fields;
        if (!@hasDecl(Of, "cid"))
            @compileError("View.Of is not component");

        const comp = self.components[self.indexOfCID(Of.cid) orelse unreachable];
        assert(comp_fields.len == comp.fields.len);

        var out: View = undefined;
        inline for (view_fields) |f| {
            const comp_idx = std.meta.fieldIndex(Of, f.name) orelse
                @compileError("field " ++ f.name ++ " not found in component");
            @field(out, f.name) = comp.fields[comp_idx].at(comp_fields[comp_idx].type, index);
        }

        return out;
    }

    pub fn atAuto(self: *const Self, comptime C: type, index: usize) util.ViewOf(C) {
        assert(0 <= index and index < self.len());

        const ti = @typeInfo(C);
        if (ti != .@"struct")
            @compileError("component should be a struct");
        if (!@hasDecl(C, "cid"))
            @compileError("type T should be a component");
        const comp = self.components[self.indexOfCID(C.cid) orelse unreachable];

        var out: util.ViewOf(C) = undefined;
        inline for (ti.@"struct".fields, 0..) |f, i| {
            @field(out, f.name) = comp.fields[i].at(f.type, index);
        }

        return out;
    }

    pub fn len(self: *const Self) usize {
        const l = self.entities.items.len;
        for (self.components) |comp|
            assert(l == comp.len());
        return l;
    }

    pub fn indexOfCID(self: *const Self, cid: u32) ?usize {
        return for (self.meta.components, 0..) |comp, idx| {
            if (comp.cid == cid) break idx;
        } else null;
    }
};

test "Archetype.Meta.from" {
    const empty = Archetype.Meta.from(&[_]type{});
    try testing.expectEqualDeep(empty, Archetype.Meta.empty);
    try testing.expectEqual(0, empty.components.len);

    const C1 = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const C2 = struct {
        pub const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };
    const expected = Archetype.Meta{ .components = ([_]MultiField.Meta{
        MultiField.Meta{
            .cid = 1,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "x", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 1, .name = "y", .size = 4, .alignment = 4 },
            })[0..],
        },
        MultiField.Meta{
            .cid = 2,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "a", .size = 1, .alignment = 1 },
                Field.Meta{ .index = 1, .name = "b", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 2, .name = "c", .size = 2, .alignment = 2 },
            })[0..],
        },
    })[0..] };
    try testing.expectEqualDeep(expected, Archetype.Meta.from(&[_]type{ C1, C2 }));
}

test "Archetype.Meta.hasComponents" {
    const C1 = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const C2 = struct {
        pub const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };

    const empty = Archetype.Meta.empty;
    try testing.expectEqual(false, empty.hasComponents(&[_]type{C1}));
    try testing.expectEqual(false, empty.hasComponents(&[_]type{C2}));
    try testing.expectEqual(false, empty.hasComponents(&[_]type{ C1, C2 }));

    const meta1 = Archetype.Meta.from(&[_]type{C1});
    try testing.expectEqual(true, meta1.hasComponents(&[_]type{C1}));
    try testing.expectEqual(false, meta1.hasComponents(&[_]type{C2}));
    try testing.expectEqual(false, meta1.hasComponents(&[_]type{ C1, C2 }));

    const meta2 = Archetype.Meta.from(&[_]type{ C1, C2 });
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{C1}));
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{C2}));
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{ C1, C2 }));
}

test "Archetype.Meta.clone" {
    const alloc = testing.allocator;

    const empty = Archetype.Meta.empty;
    const empty_clone = try empty.clone(alloc);
    defer empty_clone.deinit(alloc);
    try testing.expectEqualDeep(empty, empty_clone);

    const C1 = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const C2 = struct {
        pub const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };
    const meta = Archetype.Meta.from(&[_]type{ C1, C2 });
    const meta_clone = try meta.clone(alloc);
    defer meta_clone.deinit(alloc);
    try testing.expectEqualDeep(meta, meta_clone);
}

test "Archetype with empty Meta" {
    const alloc = testing.allocator;

    var arch = try Archetype.init(alloc, .empty);
    defer arch.deinit(alloc);

    try testing.expectEqual(0, arch.components.len);

    try arch.append(alloc, @as(Entity, 1), .{});
    try arch.append(alloc, @as(Entity, 2), .{});
    try arch.append(alloc, @as(Entity, 3), .{});
    try arch.append(alloc, @as(Entity, 4), .{});

    try testing.expectEqual(4, arch.len());

    var it = arch.iter();
    var count: usize = 0;
    while (it.next()) |entity| {
        switch (entity) {
            1...4 => {},
            else => unreachable,
        }
        count += 1;
    }
    try testing.expectEqual(4, count);
}

test "Archetype.at" {
    const alloc = testing.allocator;
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
    const VelocityView = struct {
        pub const Of = Velocity;
        x: *u32,
        y: *u32,
    };
    var archetype = try Archetype.init(alloc, .from(&[_]type{ Position, Velocity }));
    defer archetype.deinit(alloc);

    try archetype.append(alloc, @as(Entity, 0), .{ Position{ .x = 10, .y = 20 }, Velocity{ .x = 50, .y = 60 } });
    try archetype.append(alloc, @as(Entity, 1), .{ Position{ .x = 100, .y = 200 }, Velocity{ .x = 110, .y = 120 } });

    try testing.expectEqual(2, archetype.len());

    {
        const p = archetype.at(PositionView, 0);
        try testing.expectEqual(10, p.x.*);
        try testing.expectEqual(20, p.y.*);

        const pa = archetype.atAuto(Position, 0);
        try testing.expectEqual(10, pa.x.*);
        try testing.expectEqual(20, pa.y.*);

        const v = archetype.at(VelocityView, 0);
        try testing.expectEqual(50, v.x.*);
        try testing.expectEqual(60, v.y.*);

        const va = archetype.atAuto(Velocity, 0);
        try testing.expectEqual(50, va.x.*);
        try testing.expectEqual(60, va.y.*);
    }
    {
        const p = archetype.at(PositionView, 1);
        try testing.expectEqual(100, p.x.*);
        try testing.expectEqual(200, p.y.*);

        const pa = archetype.atAuto(Position, 1);
        try testing.expectEqual(100, pa.x.*);
        try testing.expectEqual(200, pa.y.*);

        const v = archetype.at(VelocityView, 1);
        try testing.expectEqual(110, v.x.*);
        try testing.expectEqual(120, v.y.*);

        const va = archetype.atAuto(Velocity, 1);
        try testing.expectEqual(110, va.x.*);
        try testing.expectEqual(120, va.y.*);
    }
}

test "Archetype.Iterator" {
    const alloc = testing.allocator;
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
    const VelocityView = struct {
        pub const Of = Velocity;
        x: *u32,
        y: *u32,
    };
    var archetype = try Archetype.init(alloc, .from(&[_]type{ Position, Velocity }));
    defer archetype.deinit(alloc);

    try archetype.append(alloc, @as(Entity, 0), .{ Position{ .x = 0, .y = 0 }, Velocity{ .x = 1, .y = 1 } });
    try archetype.append(alloc, @as(Entity, 1), .{ Position{ .x = 100, .y = 100 }, Velocity{ .x = 0, .y = 0 } });

    try testing.expectEqual(2, archetype.len());

    var it = archetype.iter();
    var count: usize = 0;
    while (it.next()) |entity| {
        count += 1;
        switch (entity) {
            0 => {
                const p = it.get(PositionView);
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);

                const pa = it.getAuto(Position);
                try testing.expectEqual(0, pa.x.*);
                try testing.expectEqual(0, pa.y.*);

                const v = it.get(VelocityView);
                try testing.expectEqual(1, v.x.*);
                try testing.expectEqual(1, v.y.*);

                const va = it.getAuto(Velocity);
                try testing.expectEqual(1, va.x.*);
                try testing.expectEqual(1, va.y.*);
            },
            1 => {
                const p = it.get(PositionView);
                try testing.expectEqual(100, p.x.*);
                try testing.expectEqual(100, p.y.*);

                const pa = it.getAuto(Position);
                try testing.expectEqual(100, pa.x.*);
                try testing.expectEqual(100, pa.y.*);

                const v = it.get(VelocityView);
                try testing.expectEqual(0, v.x.*);
                try testing.expectEqual(0, v.y.*);

                const va = it.getAuto(Velocity);
                try testing.expectEqual(0, va.x.*);
                try testing.expectEqual(0, va.y.*);
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
const Field = @import("field.zig").Field;
const MultiField = @import("multi_field.zig").MultiField;
