meta: Meta,
fields: []Field,

const Self = @This();
const Field = @import("field.zig");

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

pub fn init(gpa: mem.Allocator, meta: Meta) !Self {
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

pub fn deinit(self: *const Self, gpa: mem.Allocator) void {
    for (self.fields) |*f|
        f.deinit(gpa);
    gpa.free(self.fields);
    self.meta.deinit(gpa);
}

pub fn append(self: *Self, gpa: mem.Allocator, value: anytype) !void {
    const T = @TypeOf(value);
    const ti = @typeInfo(T);

    assert(ti == .@"struct");
    assert(@hasDecl(T, "cid"));
    assert(T.cid == self.meta.cid);
    const field_count = ti.@"struct".fields.len;
    assert(field_count == self.fields.len);

    var extracted: [field_count][]const u8 = undefined;
    inline for (ti.@"struct".fields, 0..) |f, i| {
        const field_ptr = &@field(value, f.name);
        extracted[i] = std.mem.asBytes(field_ptr);
    }

    try self.appendRaw(gpa, extracted[0..]);
}

pub fn appendRaw(self: *Self, gpa: mem.Allocator, data: []const []const u8) !void {
    assert(data.len == self.fields.len);
    for (self.fields, data, 0..) |*f, d, i| {
        f.appendRaw(gpa, d) catch |err| {
            for (0..i) |j|
                self.fields[j].pop();
            return err;
        };
    }
}

pub fn remove(self: *Self, index: usize) void {
    assert(index < self.len());
    for (self.fields) |*f| f.remove(index);
}

pub fn pop(self: *Self) void {
    self.remove(self.len() - 1);
}

pub fn len(self: *const Self) usize {
    const l = self.fields[0].len();
    for (self.fields[1..]) |f|
        assert(f.len() == l);
    return l;
}

test "MultiField.Meta.from" {
    const C1 = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    try testing.expectEqualDeep(
        Meta{
            .cid = 1,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "x", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 1, .name = "y", .size = 4, .alignment = 4 },
            })[0..],
        },
        Meta.from(C1),
    );
    const C2 = struct {
        const cid = 2;
        a: u8,
        b: u32,
        c: u16,
    };
    try testing.expectEqualDeep(
        Meta{
            .cid = 2,
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "a", .size = 1, .alignment = 1 },
                Field.Meta{ .index = 1, .name = "b", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 2, .name = "c", .size = 2, .alignment = 2 },
            })[0..],
        },
        Meta.from(C2),
    );
}

test "MultiField.Meta.clone" {
    const alloc = testing.allocator;
    const C = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    const meta = Meta.from(C);
    const meta_clone = try meta.clone(alloc);
    defer meta_clone.deinit(alloc);
    try testing.expectEqualDeep(meta, meta_clone);
}

test "MultiField.appendRaw" {
    const alloc = testing.allocator;
    const C = struct {
        const cid = 1;
        x: u32,
        y: u32,
    };
    var multi = try init(alloc, .from(C));
    defer multi.deinit(alloc);
    const data = [_][]const u8{
        &mem.toBytes(@as(u32, 0xDEADBEEF)),
        &mem.toBytes(@as(u32, 0xCAFECAFE)),
    };
    try multi.appendRaw(alloc, &data);
    try testing.expectEqual(multi.len(), 1);
    try testing.expectEqual(
        @as(u32, 0xDEADBEEF),
        mem.bytesAsValue(u32, multi.fields[0].atRaw(0)).*,
    );
    try testing.expectEqual(
        @as(u32, 0xCAFECAFE),
        mem.bytesAsValue(u32, multi.fields[1].atRaw(0)).*,
    );
}

test "MultiField.append" {
    const alloc = testing.allocator;
    const C = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    var multi = try init(alloc, .from(C));
    defer multi.deinit(alloc);
    const value = C{
        .x = 0xDEADBEEF,
        .y = 0xCAFECAFE,
    };
    try multi.append(alloc, value);
    try testing.expectEqual(multi.len(), 1);
    try testing.expectEqual(
        @as(u32, 0xDEADBEEF),
        mem.bytesAsValue(u32, multi.fields[0].atRaw(0)).*,
    );
    try testing.expectEqual(
        @as(u32, 0xCAFECAFE),
        mem.bytesAsValue(u32, multi.fields[1].atRaw(0)).*,
    );
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
