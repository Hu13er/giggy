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

    pub fn spawn(self: *Self, comptime Bundle: type, components: Bundle) !Entity {
        comptime {
            if (!util.isBundle(Bundle))
                @compileError("expected Bundle as argument");
        }

        const e = self.next_entity;
        const types = util.typesOfBundle(Bundle);
        const meta: Archetype.StaticMeta = comptime .from(types);
        var arch = try self.getOrCreateArchetype(meta);
        try arch.append(self.gpa, e, components);
        try self.entity_archetype.put(e, arch.hash);

        self.next_entity += 1;

        return e;
    }

    pub fn spawnBytes(self: *Self, entity: Entity, meta: *const Archetype.StaticMeta, bytes: []const u8) !void {
        var arch = try self.getOrCreateArchetype(meta.*);
        try arch.appendBytes(self.gpa, entity, bytes);
        try self.entity_archetype.put(entity, arch.hash);
        if (entity >= self.next_entity)
            self.next_entity = entity + 1;
    }

    pub fn reserveEntity(self: *Self) Entity {
        const e = self.next_entity;
        self.next_entity += 1;
        return e;
    }

    pub fn despawn(self: *Self, entity: Entity) bool {
        const hash = self.entity_archetype.get(entity) orelse return false;
        const arch = self.getArchetype(hash).?;
        const index = arch.indexOf(entity).?;
        const entity_removed = arch.remove(index);
        assert(entity == entity_removed);
        const entity_arch_index_removed = self.entity_archetype.swapRemove(entity);
        assert(entity_arch_index_removed);
        return true;
    }

    pub fn assign(self: *Self, entity: Entity, comptime Bundle: type, new_components: Bundle) !void {
        comptime {
            if (!util.isBundle(Bundle))
                @compileError("expected Bundle as argument");
        }

        var src_arch = self.archetypeOf(entity).?;
        const src_index = src_arch.indexOf(entity).?;
        const src_meta = src_arch.meta;

        const Ts = util.typesOfBundle(Bundle);
        const new_meta = comptime Archetype.StaticMeta.from(Ts);
        const dst_hash = src_meta.hashJoined(new_meta);

        const dst_arch = blk: {
            if (self.getArchetype(dst_hash)) |arch|
                break :blk arch;
            const dst_meta = try src_meta.join(self.gpa, new_meta);
            errdefer dst_meta.deinit(self.gpa);
            break :blk try self.createArchetypeOwned(dst_meta);
        };
        const dst_meta = dst_arch.meta;

        assert(dst_meta.components.len == src_meta.components.len + Ts.len);

        const before_size = dst_arch.len();
        errdefer dst_arch.setComponentsSize(before_size);

        const dst_index = try dst_arch.appendEntity(self.gpa, entity);
        errdefer _ = dst_arch.removeEntity(dst_index);

        try dst_arch.appendPartial(self.gpa, new_components);

        for (dst_meta.components, 0..) |comp, dst_idx| {
            if (src_arch.indexOfCID(comp.cid)) |src_idx| {
                const fields_src = src_arch
                    .components[src_idx]
                    .fields;
                const fields_dst = dst_arch
                    .components[dst_idx]
                    .fields;
                for (fields_src, fields_dst) |src, *dst|
                    try dst.appendBytes(self.gpa, src.atRaw(src_index));
            }
        }

        try self.entity_archetype.put(entity, dst_hash);

        const removed_entity = src_arch.remove(src_index);
        assert(removed_entity == entity);
    }

    pub fn assignBytes(self: *Self, entity: Entity, new_meta: *const Archetype.StaticMeta, bytes: []const u8) !void {
        var src_arch = self.archetypeOf(entity).?;
        const src_index = src_arch.indexOf(entity).?;
        const src_meta = src_arch.meta;

        const dst_hash = src_meta.hashJoined(new_meta.*);

        const dst_arch = blk: {
            if (self.getArchetype(dst_hash)) |arch|
                break :blk arch;
            const dst_meta = try src_meta.join(self.gpa, new_meta.*);
            errdefer dst_meta.deinit(self.gpa);
            break :blk try self.createArchetypeOwned(dst_meta);
        };
        const dst_meta = dst_arch.meta;

        assert(dst_meta.components.len == src_meta.components.len + new_meta.components.len);

        const before_size = dst_arch.len();
        errdefer dst_arch.setComponentsSize(before_size);

        try dst_arch.appendPartialBytes(self.gpa, new_meta.*, bytes);

        const dst_index = try dst_arch.appendEntity(self.gpa, entity);
        errdefer _ = dst_arch.removeEntity(dst_index);

        for (dst_meta.components, 0..) |comp, dst_idx| {
            if (src_arch.indexOfCID(comp.cid)) |src_idx| {
                const fields_src = src_arch
                    .components[src_idx]
                    .fields;
                const fields_dst = dst_arch
                    .components[dst_idx]
                    .fields;
                for (fields_src, fields_dst) |src, *dst|
                    try dst.appendBytes(self.gpa, src.atRaw(src_index));
            }
        }

        try self.entity_archetype.put(entity, dst_hash);

        const removed_entity = src_arch.remove(src_index);
        assert(removed_entity == entity);
    }

    pub fn unassign(self: *Self, entity: Entity, comptime Bundle: type) !void {
        comptime {
            if (!util.isBundle(Bundle)) @compileError("expected Bundle as argument");
        }
        var src_arch = self.archetypeOf(entity).?;
        const src_index = src_arch.indexOf(entity).?;
        const src_meta = src_arch.meta;

        const Ts = util.typesOfBundle(Bundle);
        const rm_meta = comptime Archetype.StaticMeta.from(Ts);
        const dst_hash = src_meta.hashDejoined(rm_meta);

        const dst_arch = blk: {
            if (self.getArchetype(dst_hash)) |arch|
                break :blk arch;
            const dst_meta = try src_meta.dejoin(self.gpa, rm_meta);
            errdefer dst_meta.deinit(self.gpa);
            break :blk try self.createArchetypeOwned(dst_meta);
        };
        const dst_meta = dst_arch.meta;

        assert(src_meta.components.len == dst_meta.components.len + Ts.len);

        const before_size = dst_arch.len();
        errdefer dst_arch.setComponentsSize(before_size);

        const dst_index = try dst_arch.appendEntity(self.gpa, entity);
        errdefer _ = dst_arch.removeEntity(dst_index);

        var c: usize = 0;
        for (dst_meta.components, 0..) |comp, dst_idx| {
            c += 1;
            const src_idx = src_arch.indexOfCID(comp.cid).?;
            const fields_src = src_arch
                .components[src_idx]
                .fields;
            const fields_dst = dst_arch
                .components[dst_idx]
                .fields;
            for (fields_src, fields_dst) |src, *dst|
                try dst.appendBytes(self.gpa, src.atRaw(src_index));
        }

        try self.entity_archetype.put(entity, dst_hash);

        const removed_entity = src_arch.remove(src_index);
        assert(removed_entity == entity);
    }

    pub fn unassignMeta(self: *Self, entity: Entity, rm_meta: *const Archetype.StaticMeta) !void {
        var src_arch = self.archetypeOf(entity).?;
        const src_index = src_arch.indexOf(entity).?;
        const src_meta = src_arch.meta;

        const dst_hash = src_meta.hashDejoined(rm_meta.*);

        const dst_arch = blk: {
            if (self.getArchetype(dst_hash)) |arch|
                break :blk arch;
            const dst_meta = try src_meta.dejoin(self.gpa, rm_meta.*);
            errdefer dst_meta.deinit(self.gpa);
            break :blk try self.createArchetypeOwned(dst_meta);
        };
        const dst_meta = dst_arch.meta;

        assert(src_meta.components.len == dst_meta.components.len + rm_meta.components.len);

        const before_size = dst_arch.len();
        errdefer dst_arch.setComponentsSize(before_size);

        const dst_index = try dst_arch.appendEntity(self.gpa, entity);
        errdefer _ = dst_arch.removeEntity(dst_index);

        for (dst_meta.components, 0..) |comp, dst_idx| {
            const src_idx = src_arch.indexOfCID(comp.cid).?;
            const fields_src = src_arch
                .components[src_idx]
                .fields;
            const fields_dst = dst_arch
                .components[dst_idx]
                .fields;
            for (fields_src, fields_dst) |src, *dst|
                try dst.appendBytes(self.gpa, src.atRaw(src_index));
        }

        try self.entity_archetype.put(entity, dst_hash);

        const removed_entity = src_arch.remove(src_index);
        assert(removed_entity == entity);
    }

    pub fn archetypeOf(self: *Self, entity: Entity) ?*Archetype {
        const hash = self.entity_archetype.get(entity) orelse return null;
        return self.archetypes.getPtr(hash);
    }

    pub fn get(self: *Self, View: type, entity: Entity) ?View {
        const arch = self.archetypeOf(entity) orelse return null;
        const index = arch.indexOf(entity).?;
        return arch.at(View, index);
    }

    pub fn getAuto(self: *Self, C: type, entity: Entity) ?util.ViewOf(C) {
        const arch = self.archetypeOf(entity) orelse return null;
        const index = arch.indexOf(entity).?;
        return arch.atAuto(C, index);
    }

    pub fn count(self: *const Self) usize {
        return self.entity_archetype.count();
    }

    pub fn countArchetype(self: *const Self) usize {
        return self.archetypes.count();
    }

    pub fn freeEmptyArchetypes(self: *Self) void {
        var it = self.archetypes.iterator();
        while (it.next()) |entry|
            _ = self.removeArchetypeIfEmpty(entry);
    }

    fn getOrCreateArchetype(self: *Self, meta: Archetype.StaticMeta) !*Archetype {
        const hash = meta.hash();
        if (self.getArchetype(hash)) |arch_ptr| return arch_ptr;
        return self.createArchetype(meta);
    }

    fn getArchetype(self: *const Self, hash: u64) ?*Archetype {
        return self.archetypes.getPtr(hash);
    }

    fn createArchetype(self: *Self, meta: Archetype.StaticMeta) !*Archetype {
        const hash = meta.hash();
        const arch = try Archetype.init(self.gpa, meta);
        try self.archetypes.put(hash, arch);
        return self.archetypes.getPtr(hash) orelse unreachable;
    }

    fn createArchetypeOwned(self: *Self, meta: Archetype.OwnedMeta) !*Archetype {
        const hash = meta.hash();
        const arch = try Archetype.initOwned(self.gpa, meta);
        try self.archetypes.put(hash, arch);
        return self.archetypes.getPtr(hash) orelse unreachable;
    }

    fn removeArchetypeIfEmpty(self: *Self, entry: ArchetypeHashMap.Entry) bool {
        if (entry.value_ptr.len() > 0) return false;
        entry.value_ptr.deinit(self.gpa);
        return self.archetypes.remove(entry.key_ptr.*);
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

        pub fn next(self: *QueryIterator) ?Entity {
            while (true) {
                if (self.current_iter) |*arch_it| {
                    if (arch_it.next()) |entity| return entity;
                }
                const next_arch = while (true) {
                    if (self.arch_iter.next()) |arch| {
                        if (arch.meta.hasCIDs(self.cids))
                            break arch;
                    } else {
                        return null;
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
                @compileError("T should be a struct");
            if (!@hasDecl(T, "cid"))
                @compileError("T should be a component");

            const found = for (self.cids) |cid| {
                if (cid == T.cid) break true;
            } else false;
            assert(found);

            return self.current_iter.?.getAuto(T);
        }
    };
};

test "World.{spawn,despawn,get}" {
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

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    const B = struct { Position, Velocity };
    const e1 = try world.spawn(B, .{
        Position{ .x = 50, .y = 60 },
        Velocity{ .x = 500, .y = 600 },
    });
    const e2 = try world.spawn(B, .{
        Position{ .x = 100, .y = 200 },
        Velocity{ .x = 1000, .y = 2000 },
    });

    try testing.expectEqual(2, world.count());
    try testing.expectEqual(1, world.countArchetype());

    {
        const p = world.get(PositionView, e1).?;
        try testing.expectEqual(50, p.x.*);
        try testing.expectEqual(60, p.y.*);
        const v = world.get(VelocityView, e1).?;
        try testing.expectEqual(500, v.x.*);
        try testing.expectEqual(600, v.y.*);
    }
    {
        const p = world.get(PositionView, e2).?;
        try testing.expectEqual(100, p.x.*);
        try testing.expectEqual(200, p.y.*);
        const v = world.get(VelocityView, e2).?;
        try testing.expectEqual(1000, v.x.*);
        try testing.expectEqual(2000, v.y.*);
    }

    try testing.expect(world.despawn(e2));
    try testing.expectEqual(1, world.count());
    try testing.expectEqual(1, world.countArchetype());
    {
        const p = world.get(PositionView, e2);
        try testing.expectEqual(null, p);
        const v = world.get(VelocityView, e2);
        try testing.expectEqual(null, v);
    }
    {
        const p = world.get(PositionView, e1).?;
        try testing.expectEqual(50, p.x.*);
        try testing.expectEqual(60, p.y.*);
        const v = world.get(VelocityView, e1).?;
        try testing.expectEqual(500, v.x.*);
        try testing.expectEqual(600, v.y.*);
    }

    try testing.expect(world.despawn(e1));
    world.freeEmptyArchetypes();

    try testing.expectEqual(0, world.count());
    try testing.expectEqual(0, world.countArchetype());
    {
        const p = world.get(PositionView, e2);
        try testing.expectEqual(null, p);
        const v = world.get(VelocityView, e2);
        try testing.expectEqual(null, v);
    }
    {
        const p = world.get(PositionView, e1);
        try testing.expectEqual(null, p);
        const v = world.get(VelocityView, e1);
        try testing.expectEqual(null, v);
    }
}

test "World.QueryIterator" {
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

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    const P = struct { Position };
    const V = struct { Velocity };
    const PV = struct { Position, Velocity };
    var entities = [_]Entity{
        // 0
        try world.spawn(PV, .{
            Position{ .x = 0, .y = 0 },
            Velocity{ .x = 100, .y = 150 },
        }),
        // 1
        try world.spawn(P, .{
            Position{ .x = 10, .y = 10 },
        }),
        // 2
        try world.spawn(PV, .{
            Position{ .x = 100, .y = 100 },
            Velocity{ .x = 500, .y = 550 },
        }),
        // 3
        try world.spawn(P, .{
            Position{ .x = 1000, .y = 1000 },
        }),
        // 4
        try world.spawn(V, .{
            Velocity{ .x = 1000, .y = 1500 },
        }),
    };
    try testing.expect(util.isUnique(Entity, &entities));

    {
        // Position
        var it = world.query(&[_]type{Position});
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const p = it.get(PositionView);
            if (entity == entities[0]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            } else if (entity == entities[1]) {
                try testing.expectEqual(10, p.x.*);
                try testing.expectEqual(10, p.y.*);
            } else if (entity == entities[2]) {
                try testing.expectEqual(100, p.x.*);
                try testing.expectEqual(100, p.y.*);
            } else if (entity == entities[3]) {
                try testing.expectEqual(1000, p.x.*);
                try testing.expectEqual(1000, p.y.*);
            } else {
                unreachable;
            }
        }
        try testing.expectEqual(4, count);
    }
    {
        // Velocity
        var it = world.query(&[_]type{Velocity});
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const v = it.get(VelocityView);
            if (entity == entities[0]) {
                try testing.expectEqual(100, v.x.*);
                try testing.expectEqual(150, v.y.*);
            } else if (entity == entities[2]) {
                try testing.expectEqual(500, v.x.*);
                try testing.expectEqual(550, v.y.*);
            } else if (entity == entities[4]) {
                try testing.expectEqual(1000, v.x.*);
                try testing.expectEqual(1500, v.y.*);
            } else {
                unreachable;
            }
        }
        try testing.expectEqual(3, count);
    }
    {
        // Position + Velocity
        var it = world.query(&[_]type{ Position, Velocity });
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const p = it.get(PositionView);
            const v = it.get(VelocityView);
            if (entity == entities[0]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
                try testing.expectEqual(100, v.x.*);
                try testing.expectEqual(150, v.y.*);
            } else if (entity == entities[2]) {
                try testing.expectEqual(100, p.x.*);
                try testing.expectEqual(100, p.y.*);
                try testing.expectEqual(500, v.x.*);
                try testing.expectEqual(550, v.y.*);
            } else {
                unreachable;
            }
        }
        try testing.expectEqual(2, count);
    }
}

test "World.{assign,unassign}" {
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

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    const P = struct { Position };
    const V = struct { Velocity };

    const entities = [_]u32{
        // 0
        try world.spawn(P, .{
            Position{ .x = 0, .y = 0 },
        }),
        // 1
        try world.spawn(P, .{
            Position{ .x = 0, .y = 0 },
        }),
    };

    try world.assign(entities[1], V, .{
        Velocity{ .x = 100, .y = 100 },
    });

    {
        // Position
        var it = world.query(&[_]type{Position});
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const p = it.get(PositionView);
            if (entity == entities[0]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            } else if (entity == entities[1]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            } else {
                std.debug.print("{d}\n", .{entity});
                unreachable;
            }
        }
        try testing.expectEqual(2, count);
    }
    {
        // Position + Velocity
        var it = world.query(&[_]type{ Position, Velocity });
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const p = it.get(PositionView);
            const v = it.get(VelocityView);
            if (entity == entities[1]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
                try testing.expectEqual(100, v.x.*);
                try testing.expectEqual(100, v.y.*);
            } else {
                unreachable;
            }
        }
        try testing.expectEqual(1, count);
    }

    try world.unassign(entities[1], V);

    {
        // Position
        var it = world.query(&[_]type{Position});
        var count: usize = 0;
        while (it.next()) |entity| {
            count += 1;
            const p = it.get(PositionView);
            if (entity == entities[0]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            } else if (entity == entities[1]) {
                try testing.expectEqual(0, p.x.*);
                try testing.expectEqual(0, p.y.*);
            } else {
                std.debug.print("{d}\n", .{entity});
                unreachable;
            }
        }
        try testing.expectEqual(2, count);
    }
    {
        // Position + Velocity
        var it = world.query(&[_]type{ Position, Velocity });
        while (it.next()) |_| {
            unreachable;
        }
    }
}

test "World.{spawnBytes,assignBytes,unassignMeta}" {
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

    const alloc = testing.allocator;
    var world = try World.init(alloc);
    defer world.deinit();

    const PV = struct { Position, Velocity };
    const P = struct { Position };
    const V = struct { Velocity };

    const entity = @as(Entity, 7);
    const bundle_pv = PV{
        Position{ .x = 11, .y = 22 },
        Velocity{ .dx = 33, .dy = 44 },
    };

    const types_pv = util.typesOfBundle(PV);
    const meta_pv: Archetype.StaticMeta = comptime .from(types_pv);
    var bytes_pv: [meta_pv.size()]u8 = undefined;
    meta_pv.extractBytes(PV, &bundle_pv, bytes_pv[0..]);
    try world.spawnBytes(entity, &meta_pv, bytes_pv[0..]);

    try testing.expectEqual(@as(usize, 1), world.count());
    const pos_view = world.getAuto(Position, entity).?;
    try testing.expectEqual(@as(u32, 11), pos_view.x.*);
    try testing.expectEqual(@as(u16, 22), pos_view.y.*);
    const vel_view = world.getAuto(Velocity, entity).?;
    try testing.expectEqual(@as(u8, 33), vel_view.dx.*);
    try testing.expectEqual(@as(u32, 44), vel_view.dy.*);

    const next = try world.spawn(P, .{
        Position{ .x = 1, .y = 2 },
    });
    try testing.expectEqual(@as(Entity, 8), next);

    const bundle_v = V{
        Velocity{ .dx = 9, .dy = 99 },
    };
    const types_v = util.typesOfBundle(V);
    const meta_v: Archetype.StaticMeta = comptime .from(types_v);
    var bytes_v: [meta_v.size()]u8 = undefined;
    meta_v.extractBytes(V, &bundle_v, bytes_v[0..]);
    try world.assignBytes(next, &meta_v, bytes_v[0..]);

    const vel_view2 = world.getAuto(Velocity, next).?;
    try testing.expectEqual(@as(u8, 9), vel_view2.dx.*);
    try testing.expectEqual(@as(u32, 99), vel_view2.dy.*);

    const types_p = util.typesOfBundle(P);
    const meta_p: Archetype.StaticMeta = comptime .from(types_p);
    try world.unassignMeta(next, &meta_p);
    const arch = world.archetypeOf(next).?;
    try testing.expect(!arch.meta.hasComponents(&[_]type{Position}));
    try testing.expect(arch.meta.hasComponents(&[_]type{Velocity}));
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const util = @import("util.zig");
const archetype = @import("archetype.zig");

const Archetype = archetype.Archetype;
const Entity = archetype.Entity;
