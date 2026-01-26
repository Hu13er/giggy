pub const Archetype = struct {
    meta: Meta,
    components: []MultiField,
    hash: u64,

    const Self = @This();

    pub const Meta = struct {
        components: []const MultiField.Meta,

        pub inline fn from(comptime Ts: []const type) Meta {
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

        pub fn next(self: *Iterator) bool {
            if (self.next_index >= self.archetype.len()) return false;
            self.next_index += 1;
            return true;
        }

        pub fn get(self: *const Iterator, comptime View: type) View {
            assert(self.next_index > 0);

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

            const comp = self.archetype.components[self.archetype.indexOfCID(Of.cid) orelse unreachable];
            assert(comp_fields.len == comp.fields.len);

            var out: View = undefined;
            inline for (view_fields) |f| {
                const comp_idx = std.meta.fieldIndex(Of, f.name) orelse
                    @compileError("field " ++ f.name ++ " not found in component");
                @field(out, f.name) = comp.fields[comp_idx].at(comp_fields[comp_idx].type, self.next_index - 1);
            }

            return out;
        }

        pub fn getAuto(self: *const Iterator, comptime T: type) util.ViewOf(T) {
            assert(self.next_index > 0);

            const ti = @typeInfo(T);
            if (ti != .@"struct")
                @compileError("component should be a struct");
            if (!@hasDecl(T, "cid"))
                @compileError("type T should be a component");
            const comp = self.archetype.components[self.archetype.indexOfCID(T.cid) orelse unreachable];

            var out: util.ViewOf(T) = undefined;
            inline for (ti.@"struct".fields, 0..) |f, i| {
                @field(out, f.name) = comp.fields[i].at(f.type, self.next_index - 1);
            }

            return out;
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
            .components = comps,
            .hash = meta.hash(),
        };
    }

    pub fn deinit(self: *Self, gpa: mem.Allocator) void {
        for (self.components) |comp|
            comp.deinit(gpa);
        gpa.free(self.components);
        self.meta.deinit(gpa);
    }

    pub fn append(self: *Self, gpa: mem.Allocator, component_list: anytype) !void {
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

        inline for (fields, cid_indexes, 0..) |f, cid_idx, i| {
            const value = @field(component_list, f.name);
            self.components[cid_idx].append(gpa, value) catch |err| {
                for (0..i) |j|
                    self.components[cid_indexes[j]].pop();
                return err;
            };
        }
    }

    pub fn appendRaw(self: *Self, gpa: mem.Allocator, data: []const []const []const u8) !void {
        assert(data.len == self.components.len);
        for (self.components, data, 0..) |*c, d, i| {
            c.appendRaw(gpa, d) catch |err| {
                for (0..i) |j|
                    self.components[j].pop();
                return err;
            };
        }
    }

    pub fn remove(self: *Self, index: usize) void {
        assert(index < self.len());
        for (self.components) |comp|
            comp.remove(index);
    }

    pub fn pop(self: *Self) void {
        self.remove(self.len() - 1);
    }

    pub fn len(self: *const Self) usize {
        if (self.components.len == 0) return 0;
        const l = self.components[0].len();
        for (self.components[1..]) |comp|
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

    try archetype.append(alloc, .{ Position{ .x = 0, .y = 0 }, Velocity{ .x = 1, .y = 1 } });
    try archetype.append(alloc, .{ Position{ .x = 100, .y = 100 }, Velocity{ .x = 0, .y = 0 } });

    try testing.expectEqual(2, archetype.len());

    var it = archetype.iter();

    try testing.expect(it.next() == true);

    const p1v = it.get(PositionView);
    try testing.expectEqual(0, p1v.x.*);
    try testing.expectEqual(0, p1v.y.*);
    const p1 = it.getAuto(Position);
    try testing.expectEqual(0, p1.x.*);
    try testing.expectEqual(0, p1.y.*);

    const v1v = it.get(VelocityView);
    try testing.expectEqual(1, v1v.x.*);
    try testing.expectEqual(1, v1v.y.*);
    const v1 = it.getAuto(Velocity);
    try testing.expectEqual(1, v1.x.*);
    try testing.expectEqual(1, v1.y.*);

    try testing.expect(it.next() == true);

    const p2v = it.get(PositionView);
    try testing.expectEqual(100, p2v.x.*);
    try testing.expectEqual(100, p2v.y.*);
    const p2 = it.getAuto(Position);
    try testing.expectEqual(100, p2.x.*);
    try testing.expectEqual(100, p2.y.*);

    const v2v = it.get(VelocityView);
    try testing.expectEqual(0, v2v.x.*);
    try testing.expectEqual(0, v2v.y.*);
    const v2 = it.get(VelocityView);
    try testing.expectEqual(0, v2.x.*);
    try testing.expectEqual(0, v2.y.*);

    try testing.expect(it.next() == false);
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const util = @import("util.zig");
const Field = @import("field.zig").Field;
const MultiField = @import("multi_field.zig").MultiField;
