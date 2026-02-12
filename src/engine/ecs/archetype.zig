pub const Entity = u32;

pub const Archetype = struct {
    meta: OwnedMeta,
    entities: EntityList,
    entities_index: EntityIndexHashmap,
    components: []MultiField,
    hash: u64,

    const Self = @This();
    const EntityList = std.ArrayList(Entity);
    const EntityIndexHashmap = std.AutoHashMap(Entity, usize);

    pub const StaticMeta = Meta(.static);
    pub const OwnedMeta = Meta(.owned);

    pub const MetaKind = enum { static, owned };

    pub fn Meta(comptime kind: MetaKind) type {
        return struct {
            components: []const *const MultiField.Meta,

            const MetaSelf = @This();

            pub const empty: MetaSelf = if (kind == .static)
                .{ .components = &[_]*const MultiField.Meta{} }
            else
                @compileError("Meta(.owned) has no empty constant");

            pub inline fn from(comptime Ts: []const type) MetaSelf {
                comptime if (kind != .static)
                    @compileError("Meta(.owned) cannot be constructed from types");
                if (Ts.len == 0)
                    return empty;
                const metas = comptime blk: {
                    var tmp: [Ts.len]*const MultiField.Meta = undefined;
                    for (Ts, 0..) |T, i| {
                        tmp[i] = MultiField.Meta.from(T);
                    }
                    std.sort.insertion(*const MultiField.Meta, &tmp, {}, struct {
                        fn lessThan(_: void, a: *const MultiField.Meta, b: *const MultiField.Meta) bool {
                            return a.cid < b.cid;
                        }
                    }.lessThan);

                    break :blk tmp;
                };
                inline for (1..metas.len) |i| {
                    assert(metas[i - 1].cid != metas[i].cid);
                }
                return .{ .components = &metas };
            }

            pub fn join(self: *const MetaSelf, gpa: mem.Allocator, with: StaticMeta) !OwnedMeta {
                var out = try std.ArrayList(*const MultiField.Meta)
                    .initCapacity(gpa, self.components.len + with.components.len);
                errdefer out.deinit(gpa);
                const i_comp = self.components;
                const j_comp = with.components;
                var i: usize = 0;
                var j: usize = 0;
                while (true) {
                    const plus_i = i < i_comp.len and
                        (j >= j_comp.len or i_comp[i].cid < j_comp[j].cid);
                    const plus_j = j < j_comp.len and
                        (i >= i_comp.len or j_comp[j].cid <= i_comp[i].cid);
                    var to_add: *const MultiField.Meta = undefined;
                    if (plus_i) {
                        to_add = i_comp[i];
                        i += 1;
                    } else if (plus_j) {
                        to_add = j_comp[j];
                        j += 1;
                    } else {
                        break;
                    }
                    if (out.getLastOrNull()) |last| {
                        if (last.cid == to_add.cid) continue;
                        assert(last.cid < to_add.cid);
                    }
                    try out.append(gpa, to_add);
                }
                return .{ .components = try out.toOwnedSlice(gpa) };
            }

            pub fn dejoin(self: *const MetaSelf, gpa: mem.Allocator, with: StaticMeta) !OwnedMeta {
                var out = try std.ArrayList(*const MultiField.Meta).initCapacity(gpa, blk: {
                    if (self.components.len < with.components.len)
                        break :blk self.components.len;
                    break :blk self.components.len - with.components.len;
                });
                errdefer out.deinit(gpa);

                const j_comp = with.components;
                var j: usize = 0;
                for (self.components) |comp| {
                    while (j < j_comp.len and j_comp[j].cid < comp.cid) : (j += 1) {}
                    if (j < j_comp.len and j_comp[j].cid == comp.cid)
                        continue;
                    try out.append(gpa, comp);
                }

                return .{ .components = try out.toOwnedSlice(gpa) };
            }

            pub fn copy(self: *const MetaSelf, gpa: mem.Allocator) !OwnedMeta {
                const comps = try gpa.alloc(*const MultiField.Meta, self.components.len);
                @memcpy(comps, self.components);
                return .{ .components = comps };
            }

            pub inline fn view(self: *const MetaSelf) StaticMeta {
                return .{ .components = self.components };
            }

            pub fn deinit(self: *const MetaSelf, gpa: mem.Allocator) void {
                comptime if (kind != .owned)
                    @compileError("Meta(.static) cannot be deinitialized");
                gpa.free(self.components);
            }

            pub fn hash(self: *const MetaSelf) u64 {
                var hasher = std.hash.Wyhash.init(0);
                for (self.components) |comp|
                    hasher.update(mem.asBytes(&comp.cid));
                return hasher.final();
            }

            pub fn hashJoined(self: *const MetaSelf, with: StaticMeta) u64 {
                var hasher = std.hash.Wyhash.init(0);

                const i_comp = self.components;
                const j_comp = with.components;
                var i: usize = 0;
                var j: usize = 0;
                var last: ?u32 = null;

                while (true) {
                    const plus_i = i < i_comp.len and
                        (j >= j_comp.len or i_comp[i].cid < j_comp[j].cid);
                    const plus_j = j < j_comp.len and
                        (i >= i_comp.len or j_comp[j].cid <= i_comp[i].cid);
                    var to_add: u32 = undefined;
                    if (plus_i) {
                        to_add = i_comp[i].cid;
                        i += 1;
                    } else if (plus_j) {
                        to_add = j_comp[j].cid;
                        j += 1;
                    } else {
                        break;
                    }
                    if (last) |l| assert(l != to_add);
                    hasher.update(mem.asBytes(&to_add));
                    last = to_add;
                }

                return hasher.final();
            }

            pub fn hashDejoined(self: *const MetaSelf, with: StaticMeta) u64 {
                var hasher = std.hash.Wyhash.init(0);

                const j_comp = with.components;
                var j: usize = 0;
                for (self.components) |comp| {
                    while (j < j_comp.len and j_comp[j].cid < comp.cid) : (j += 1) {}
                    if (j < j_comp.len and j_comp[j].cid == comp.cid)
                        continue;
                    hasher.update(mem.asBytes(&comp.cid));
                }

                return hasher.final();
            }

            pub inline fn extractBytes(self: *const MetaSelf, comptime Bundle: type, value: *const Bundle, out: []u8) void {
                comptime if (!util.isBundle(Bundle)) @compileError("expected Bundle as argument");

                assert(out.len == self.size());

                const ti = @typeInfo(Bundle);
                const fields = ti.@"struct".fields;

                const Entry = struct {
                    cid: u32,
                    offset: usize,
                    T: type,
                };

                const entries = comptime blk: {
                    var tmp: [fields.len]Entry = undefined;
                    for (fields, 0..) |f, i| {
                        const T = f.type;
                        util.assertComponent(T);
                        const cid = util.cidOf(T);
                        tmp[i] = .{
                            .cid = cid,
                            .offset = @offsetOf(Bundle, f.name),
                            .T = T,
                        };
                    }
                    break :blk tmp;
                };

                var idx: usize = 0;
                for (self.components) |comp| {
                    const s = comp.size();
                    const base_ptr = @intFromPtr(value);
                    inline for (entries) |e| {
                        if (e.cid == comp.cid) {
                            const field_ptr = @as(*e.T, @ptrFromInt(base_ptr + e.offset));
                            comp.extractBytes(e.T, field_ptr, out[idx .. idx + s]);
                            break;
                        }
                    } else {
                        unreachable;
                    }
                    idx += s;
                }
                assert(idx == self.size());
            }

            pub fn hasComponents(self: *const MetaSelf, comptime Comps: []const type) bool {
                var cids: [Comps.len]u32 = undefined;
                inline for (Comps, 0..) |C, i| {
                    comptime util.assertComponent(C);
                    const cid = comptime util.cidOf(C);
                    cids[i] = cid;
                }
                return self.hasCIDs(cids[0..]);
            }

            pub fn hasCIDs(self: *const MetaSelf, cids: []const u32) bool {
                for (cids) |cid| {
                    const found = for (self.components) |comp| {
                        if (comp.cid == cid) break true;
                    } else false;
                    if (!found) return false;
                }
                return true;
            }

            pub fn size(self: *const MetaSelf) usize {
                var sum: usize = 0;
                for (self.components) |comp| sum += comp.size();
                return sum;
            }
        };
    }

    pub const Iterator = struct {
        archetype: *Self,
        next_index: usize,

        pub fn next(self: *Iterator) ?Entity {
            if (self.next_index >= self.archetype.len()) {
                self.next_index += 1; // Mark exhausted so get()/getAuto() fail
                return null;
            }
            self.next_index += 1;
            return self.archetype.entities.items[self.next_index - 1];
        }

        pub fn get(self: *const Iterator, comptime View: type) View {
            assert(self.next_index > 0 and self.next_index <= self.archetype.len());
            return self.archetype.at(View, self.next_index - 1);
        }

        pub fn getAuto(self: *const Iterator, comptime C: type) util.ViewOf(C) {
            assert(self.next_index > 0 and self.next_index <= self.archetype.len());
            return self.archetype.atAuto(C, self.next_index - 1);
        }
    };

    pub fn iter(self: *Self) Iterator {
        return .{
            .archetype = self,
            .next_index = 0,
        };
    }

    pub fn init(gpa: mem.Allocator, meta: StaticMeta) !Self {
        const owned = try meta.copy(gpa);
        return initOwned(gpa, owned);
    }

    pub fn initOwned(gpa: mem.Allocator, meta: OwnedMeta) !Self {
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
            .meta = meta,
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
        const fields_len = ti.@"struct".fields.len;
        assert(fields_len == self.components.len);

        const index = try self.appendEntity(gpa, entity);
        errdefer _ = self.removeEntity(index);
        try self.appendPartial(gpa, component_list);
    }

    pub fn appendPartial(self: *Self, gpa: mem.Allocator, component_list: anytype) !void {
        const ti = @typeInfo(@TypeOf(component_list));
        assert(ti == .@"struct");
        const fields = ti.@"struct".fields;

        var cid_indexes: [fields.len]usize = undefined;
        inline for (fields, 0..) |f, i| {
            const T = f.type;
            comptime util.assertComponent(T);
            const cid = comptime util.cidOf(T);
            cid_indexes[i] = self.indexOfCID(cid) orelse unreachable;
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

    pub fn appendBytes(self: *Self, gpa: mem.Allocator, entity: Entity, bytes: []const u8) !void {
        const before_size = self.len();
        try self.appendPartialBytes(gpa, self.meta.view(), bytes);
        errdefer self.setComponentsSize(before_size);
        _ = try self.appendEntity(gpa, entity);
    }

    pub fn appendPartialBytes(self: *Self, gpa: mem.Allocator, meta: StaticMeta, bytes: []const u8) !void {
        const expected_len = meta.size();
        assert(bytes.len == expected_len);

        const before_size = self.len();
        errdefer self.setComponentsSize(before_size);

        var idx: usize = 0;
        for (meta.components) |comp| {
            const cid_idx = self.indexOfCID(comp.cid).?;
            const size: usize = comp.size();
            try self.components[cid_idx].appendBytes(gpa, bytes[idx .. idx + size]);
            idx += size;
        }
        assert(idx == expected_len);
    }

    pub fn appendEntity(self: *Self, gpa: mem.Allocator, entity: Entity) !usize {
        const new_index = self.entities.items.len;
        try self.entities_index.put(entity, new_index);
        errdefer _ = self.entities_index.remove(entity);
        try self.entities.append(gpa, entity);
        return new_index;
    }

    pub fn appendRaw(self: *Self, gpa: mem.Allocator, entity: Entity, data: []const []const []const u8) !void {
        assert(data.len == self.components.len);
        try self.entities_index.put(entity, self.len());
        errdefer self.entities_index.remove(entity);
        try self.entities.append(gpa, entity);
        errdefer _ = self.entities.pop();
        for (self.components, data, 0..) |*c, d, i| {
            c.appendBytes(gpa, d) catch |err| {
                for (0..i) |j|
                    self.components[j].pop();
                return err;
            };
        }
    }

    pub fn remove(self: *Self, index: usize) Entity {
        assert(index < self.len());
        const entity = self.removeEntity(index);
        for (self.components) |*comp|
            comp.remove(index);
        return entity;
    }

    pub fn removeEntity(self: *Self, index: usize) Entity {
        const old_len = self.entities.items.len;
        const entity = self.entities.swapRemove(index);

        const new_len = old_len - 1;
        if (index < new_len) {
            const swapped_entity = self.entities.items[index];
            const entry = self.entities_index.getEntry(swapped_entity) orelse unreachable;
            entry.value_ptr.* = index;
        }

        _ = self.entities_index.remove(entity);
        return entity;
    }

    pub fn pop(self: *Self) Entity {
        assert(self.len() > 0);
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
        comptime util.assertComponent(Of);
        const of_cid = comptime util.cidOf(Of);

        const comp = self.components[self.indexOfCID(of_cid) orelse unreachable];
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
        comptime util.assertComponent(C);
        const cid = comptime util.cidOf(C);
        const comp = self.components[self.indexOfCID(cid) orelse unreachable];

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

    pub fn setComponentsSize(self: *Self, size: usize) void {
        for (self.components) |*comp|
            comp.setSize(size);
    }

    pub fn indexOfCID(self: *const Self, cid: u32) ?usize {
        return for (self.meta.components, 0..) |comp, idx| {
            if (comp.cid == cid) break idx;
        } else null;
    }
};

test "Archetype.Meta.from" {
    const empty = Archetype.StaticMeta.from(&[_]type{});
    try testing.expectEqualDeep(empty, Archetype.StaticMeta.empty);
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
    const expected = Archetype.StaticMeta{ .components = &[_]*const MultiField.Meta{
        MultiField.Meta.from(C1),
        MultiField.Meta.from(C2),
    } };
    try testing.expectEqualDeep(expected, Archetype.StaticMeta.from(&[_]type{ C1, C2 }));
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

    const empty = Archetype.StaticMeta.empty;
    try testing.expectEqual(false, empty.hasComponents(&[_]type{C1}));
    try testing.expectEqual(false, empty.hasComponents(&[_]type{C2}));
    try testing.expectEqual(false, empty.hasComponents(&[_]type{ C1, C2 }));

    const meta1 = Archetype.StaticMeta.from(&[_]type{C1});
    try testing.expectEqual(true, meta1.hasComponents(&[_]type{C1}));
    try testing.expectEqual(false, meta1.hasComponents(&[_]type{C2}));
    try testing.expectEqual(false, meta1.hasComponents(&[_]type{ C1, C2 }));

    const meta2 = Archetype.StaticMeta.from(&[_]type{ C1, C2 });
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{C1}));
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{C2}));
    try testing.expectEqual(true, meta2.hasComponents(&[_]type{ C1, C2 }));
}

test "Archetype.Meta.join" {
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

    const meta1: Archetype.StaticMeta = .from(&[_]type{C1});
    const meta2: Archetype.StaticMeta = .from(&[_]type{C2});
    const meta_joined = try meta1.join(alloc, meta2);
    defer meta_joined.deinit(alloc);

    const meta_expected: Archetype.StaticMeta = .from(&[_]type{ C1, C2 });
    try testing.expectEqualDeep(meta_expected, meta_joined.view());
}

test "Archetype.Meta.dejoin" {
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

    const meta1: Archetype.StaticMeta = .from(&[_]type{ C1, C2 });
    const meta2: Archetype.StaticMeta = .from(&[_]type{C2});
    const meta_dejoined = try meta1.dejoin(alloc, meta2);
    defer meta_dejoined.deinit(alloc);

    const meta_expected: Archetype.StaticMeta = .from(&[_]type{C1});
    try testing.expectEqualDeep(meta_expected, meta_dejoined.view());
}

test "Archetype.Meta.copy" {
    const alloc = testing.allocator;

    const empty = Archetype.StaticMeta.empty;
    const empty_copy = try empty.copy(alloc);
    defer empty_copy.deinit(alloc);
    try testing.expectEqualDeep(empty, empty_copy.view());

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
    const meta = Archetype.StaticMeta.from(&[_]type{ C1, C2 });
    const meta_copy = try meta.copy(alloc);
    defer meta_copy.deinit(alloc);
    try testing.expectEqualDeep(meta, meta_copy.view());
}

test "Archetype.Meta.extractBytes" {
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

    const meta: Archetype.StaticMeta = comptime .from(&[_]type{ Velocity, Position });
    try testing.expectEqual(@as(usize, 11), meta.size());

    const bundle = Bundle{
        .vel = .{ .dx = 0x77, .dy = 0x8899AABB },
        .pos = .{ .x = 0x11223344, .y = 0x5566 },
    };

    var out: [meta.size()]u8 = undefined;
    meta.extractBytes(Bundle, &bundle, out[0..]);

    const pos_x_size = @sizeOf(u32);
    const pos_y_size = @sizeOf(u16);
    const vel_dx_size = @sizeOf(u8);

    const pos_x = mem.bytesAsValue(u32, out[0..pos_x_size]).*;
    const pos_y = mem.bytesAsValue(u16, out[pos_x_size .. pos_x_size + pos_y_size]).*;
    const vel_dx = mem.bytesAsValue(u8, out[pos_x_size + pos_y_size .. pos_x_size + pos_y_size + vel_dx_size]).*;
    const vel_dy = mem.bytesAsValue(u32, out[pos_x_size + pos_y_size + vel_dx_size .. meta.size()]).*;

    try testing.expectEqual(@as(u32, 0x11223344), pos_x);
    try testing.expectEqual(@as(u16, 0x5566), pos_y);
    try testing.expectEqual(@as(u8, 0x77), vel_dx);
    try testing.expectEqual(@as(u32, 0x8899AABB), vel_dy);
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

test "Archetype.appendBytes" {
    const alloc = testing.allocator;
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
        pos: Position,
        vel: Velocity,
    };

    const meta: Archetype.StaticMeta = comptime .from(&[_]type{ Position, Velocity });
    var archetype = try Archetype.init(alloc, meta);
    defer archetype.deinit(alloc);

    const bundle = Bundle{
        .pos = .{ .x = 0x11223344, .y = 0x5566 },
        .vel = .{ .dx = 0x77, .dy = 0x8899AABB },
    };

    var bytes: [meta.size()]u8 = undefined;
    meta.extractBytes(Bundle, &bundle, bytes[0..]);
    try archetype.appendBytes(alloc, @as(Entity, 1), bytes[0..]);

    try testing.expectEqual(@as(usize, 1), archetype.len());
    const pos = archetype.atAuto(Position, 0);
    const vel = archetype.atAuto(Velocity, 0);
    try testing.expectEqual(@as(u32, 0x11223344), pos.x.*);
    try testing.expectEqual(@as(u16, 0x5566), pos.y.*);
    try testing.expectEqual(@as(u8, 0x77), vel.dx.*);
    try testing.expectEqual(@as(u32, 0x8899AABB), vel.dy.*);
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
    var archetype = try Archetype.init(alloc, Archetype.StaticMeta.from(&[_]type{ Position, Velocity }));
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
    var archetype = try Archetype.init(alloc, Archetype.StaticMeta.from(&[_]type{ Position, Velocity }));
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
