const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

pub const Field = struct {
    meta: Meta,
    buffer: Buffer,

    pub const Meta = struct {
        index: usize,
        name: ?[:0]const u8,
        size: usize,
        alignment: usize,

        pub inline fn fromScalar(comptime T: type) Meta {
            return .{
                .index = 0,
                .name = null,
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
            };
        }

        pub inline fn fromStruct(comptime T: type, comptime index: usize) Meta {
            const ti = @typeInfo(T);
            assert(ti == .@"struct");
            const field = ti.@"struct".fields[index];
            return .{
                .index = index,
                .name = field.name,
                .size = @sizeOf(field.type),
                .alignment = @alignOf(field.type),
            };
        }
    };

    const Buffer = std.ArrayListAligned(u8, max_alignment);
    const max_alignment = mem.Alignment.@"64";

    pub fn init(gpa: mem.Allocator, meta: Meta) !Field {
        assert(meta.alignment <= max_alignment.toByteUnits());
        return .{
            .meta = meta,
            .buffer = try Buffer.initCapacity(gpa, 1),
        };
    }

    pub fn deinit(self: *Field, gpa: mem.Allocator) void {
        self.buffer.deinit(gpa);
    }

    pub fn append(self: *Field, gpa: mem.Allocator, data: []const u8) !void {
        assert(data.len == self.meta.size);
        try self.buffer.appendSlice(gpa, data);
    }

    // remove `index` from field
    // Assums that @mod(buffer.items.len, self.meta.size) == 0
    pub fn remove(self: *Field, index: usize) void {
        if (self.buffer.items.len < self.meta.size) return; // empty
        if (self.buffer.items.len > self.meta.size) {
            // swap with last
            const start = index * self.meta.size;
            const end = start + self.meta.size;
            const last_end = self.buffer.items.len;
            const last_start = last_end - self.meta.size;
            @memmove(self.buffer.items[start..end], self.buffer.items[last_start..last_end]);
        }
        self.buffer.items.len -= self.meta.size;
    }

    pub fn pop(self: *Field) void {
        self.remove(self.len() - 1);
    }

    pub fn len(self: *const Field) usize {
        return self.buffer.items.len / self.meta.size;
    }

    pub inline fn at(self: *Field, index: usize) []u8 {
        const start = index * self.meta.size;
        return self.buffer.items[start .. start + self.meta.size];
    }
};

test "test Field.Meta" {
    // test fromScaler
    try testing.expectEqualDeep(
        Field.Meta{
            .index = 0,
            .name = null,
            .size = 1,
            .alignment = 1,
        },
        Field.Meta.fromScalar(u8),
    );
    try testing.expectEqualDeep(
        Field.Meta{
            .index = 0,
            .name = null,
            .size = 2,
            .alignment = 2,
        },
        Field.Meta.fromScalar(u16),
    );
    // test fromStruct
    const T = struct {
        a: u8,
        b: u16,
    };
    try testing.expectEqualDeep(
        Field.Meta{
            .index = 0,
            .name = "a",
            .size = 1,
            .alignment = 1,
        },
        Field.Meta.fromStruct(T, 0),
    );
    try testing.expectEqualDeep(
        Field.Meta{
            .index = 1,
            .name = "b",
            .size = 2,
            .alignment = 2,
        },
        Field.Meta.fromStruct(T, 1),
    );
}

test "test Field" {
    const alloc = testing.allocator;
    var f1 = try Field.init(alloc, .fromScalar(u8));
    defer f1.deinit(alloc);
    try f1.append(alloc, &[_]u8{0x88});
    try testing.expectEqual(@as(u8, 0x88), mem.bytesAsValue(u8, f1.at(0)).*);
    f1.remove(0);
    try testing.expect(f1.len() == 0);

    var f2 = try Field.init(alloc, .fromScalar(u32));
    defer f2.deinit(alloc);
    const test_cases = [_]u32{
        0x00000000,
        0xDEADBEEF,
        0xCAFE8808,
        0xFFFFFFFF,
    };
    for (test_cases) |tc| {
        try f2.append(alloc, mem.asBytes(&tc));
    }
    for (test_cases, 0..) |expected, idx| {
        const actual_bytes = f2.at(idx);
        try testing.expectEqual(expected, mem.bytesAsValue(u32, actual_bytes).*);
    }
}

pub const MultiField = struct {
    meta: Meta,
    fields: []Field,

    pub const Meta = struct {
        cid: u32,
        fields: []const Field.Meta,

        pub inline fn from(comptime T: type) Meta {
            const ti = @typeInfo(T);
            assert(ti == .@"struct");
            assert(@hasDecl(T, "cid"));
            const cid = T.cid;
            const l = ti.@"struct".fields.len;
            var fs: [l]Field.Meta = undefined;
            inline for (0..l) |idx| {
                fs[idx] = .fromStruct(T, idx);
            }
            return .{ .cid = cid, .fields = &fs };
        }

        pub fn clone(self: *const Meta, gpa: mem.Allocator) !Meta {
            var fs = try gpa.alloc(Field.Meta, self.fields.len);
            for (self.fields, 0..) |f, i|
                fs[i] = f;
            return .{ .cid = self.cid, .fields = fs };
        }

        pub fn deinit(self: *const Meta, gpa: mem.Allocator) void {
            gpa.free(self.fields);
        }
    };

    pub fn init(gpa: mem.Allocator, meta: Meta) !MultiField {
        var fs = try gpa.alloc(Field, meta.fields.len);
        errdefer gpa.free(fs);
        for (meta.fields, 0..) |field_meta, i| {
            fs[i] = Field.init(gpa, field_meta) catch |err| {
                for (0..i) |j|
                    fs[j].deinit(gpa);
                return err;
            };
        }
        return .{
            .meta = try meta.clone(gpa),
            .fields = fs,
        };
    }

    pub fn deinit(self: *MultiField, gpa: mem.Allocator) void {
        for (self.fields) |*f|
            f.deinit(gpa);
        gpa.free(self.fields);
        self.meta.deinit(gpa);
    }

    pub fn appendRaw(self: *MultiField, gpa: mem.Allocator, data: []const []const u8) !void {
        assert(data.len == self.fields.len);
        for (self.fields, data, 0..) |*f, d, i| {
            f.append(gpa, d) catch |err| {
                for (0..i) |j|
                    self.fields[j].pop();
                return err;
            };
        }
    }

    pub fn remove(self: *MultiField, index: usize) void {
        assert(index < self.len());
        for (self.fields) |f| f.remove(index);
    }

    pub fn pop(self: *MultiField) void {
        self.remove(self.len() - 1);
    }

    pub fn len(self: *const MultiField) usize {
        const l = self.fields[0].len();
        for (self.fields[1..]) |f|
            assert(f.len() == l);
        return l;
    }
};

test "test MultiField.Meta.from" {
    const C1 = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    try testing.expectEqualDeep(
        MultiField.Meta{
            .cid = 1,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "x", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 1, .name = "y", .size = 4, .alignment = 4 },
            })[0..],
        },
        MultiField.Meta.from(C1),
    );
    const C2 = struct {
        const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };
    try testing.expectEqualDeep(
        MultiField.Meta{
            .cid = 2,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "a", .size = 1, .alignment = 1 },
                Field.Meta{ .index = 1, .name = "b", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 2, .name = "c", .size = 2, .alignment = 2 },
            })[0..],
        },
        MultiField.Meta.from(C2),
    );
}

test "test MultiField.Meta.clone" {
    const alloc = testing.allocator;
    const C = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    const meta = MultiField.Meta.from(C);
    const meta_clone = try meta.clone(alloc);
    defer meta_clone.deinit(alloc);
    try testing.expectEqualDeep(meta, meta_clone);
}

pub const Archetype = struct {
    meta: Meta,
    components: []MultiField,

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
    };

    pub fn init(gpa: mem.Allocator, meta: Meta) !Archetype {
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
        };
    }

    pub fn deinit(self: *Archetype, gpa: mem.Allocator) void {
        for (self.components) |comp|
            comp.deinit(gpa);
        gpa.free(self.components);
        self.meta.deinit(gpa);
    }

    pub fn appendRaw(self: *Archetype, gpa: mem.Allocator, data: []const []const []const u8) !void {
        assert(data.len == self.components.len);
        for (self.components, data, 0..) |*c, d, i| {
            c.appendRaw(gpa, d) catch |err| {
                for (0..i) |j|
                    self.components[j].pop();
                return err;
            };
        }
    }

    pub fn remove(self: *Archetype, index: usize) void {
        assert(index < self.len());
        for (self.components) |comp|
            comp.remove(index);
    }

    pub fn pop(self: *Archetype) void {
        self.remove(self.len() - 1);
    }

    pub fn len(self: *const Archetype) usize {
        const l = self.components[0].len();
        for (self.components[1..]) |comp|
            assert(l == comp.len());
        return l;
    }
};

test "test Archetype.Meta.from" {
    const C1 = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    const C2 = struct {
        const cid = 2;
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

test "test Archetype.Meta.clone" {
    const alloc = testing.allocator;
    const C1 = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    const C2 = struct {
        const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };
    const meta = Archetype.Meta.from(&[_]type{ C1, C2 });
    const meta_clone = try meta.clone(alloc);
    defer meta_clone.deinit(alloc);
    try testing.expectEqualDeep(meta, meta_clone);
}
