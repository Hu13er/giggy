pub const MultiField = struct {
    meta: *const Meta,
    fields: []Field,

    const Self = @This();

    pub const Meta = struct {
        cid: u32,
        fields: []const Field.Meta,

        pub inline fn from(comptime T: type) *const Meta {
            return &struct {
                pub const v: Meta = meta_blk: {
                    util.assertComponent(T);
                    const cid = util.cidOf(T);
                    const ti = @typeInfo(T);
                    const l = ti.@"struct".fields.len;
                    const fs = fs_blk: {
                        var tmp: [l]Field.Meta = undefined;
                        for (0..l) |i| tmp[i] = Field.Meta.fromStruct(T, i).*;
                        break :fs_blk tmp;
                    };
                    break :meta_blk .{ .cid = cid, .fields = &fs };
                };
            }.v;
        }

        pub fn extractRaw(self: *const Meta, comptime T: type, value: *const T, out: [][]const u8) void {
            comptime util.assertComponent(T);
            const cid = comptime util.cidOf(T);
            const ti = @typeInfo(T);
            assert(cid == self.cid);
            const fields = ti.@"struct".fields;
            assert(fields.len == self.fields.len);

            inline for (fields, 0..) |f, i| {
                const base_ptr = @intFromPtr(value);
                const offset = @offsetOf(T, f.name);
                const field_ptr = @as(*f.type, @ptrFromInt(base_ptr + offset));
                out[i] = std.mem.asBytes(field_ptr);
            }
        }

        pub inline fn extractBytes(self: *const Meta, comptime T: type, value: *const T, out: []u8) void {
            comptime util.assertComponent(T);
            const cid = comptime util.cidOf(T);
            assert(cid == self.cid);
            const ti = @typeInfo(T);
            const fields = ti.@"struct".fields;
            assert(fields.len == self.fields.len);

            assert(out.len == self.size());

            var idx: usize = 0;
            inline for (fields, 0..) |f, i| {
                const base_ptr = @intFromPtr(value);
                const offset = @offsetOf(T, f.name);
                const field_ptr = @as(*f.type, @ptrFromInt(base_ptr + offset));
                const s = self.fields[i].size;
                assert(s == @sizeOf(f.type));
                @memcpy(out[idx .. idx + s], std.mem.asBytes(field_ptr));
                idx += s;
            }
            assert(idx == self.size());
        }

        pub fn size(self: *const Meta) usize {
            var sum: usize = 0;
            for (self.fields) |f| sum += f.size;
            return sum;
        }
    };

    pub fn init(gpa: mem.Allocator, meta: *const Meta) !Self {
        var fs = try gpa.alloc(Field, meta.fields.len);
        errdefer gpa.free(fs);
        for (meta.fields, 0..) |_, i| {
            fs[i] = Field.init(gpa, &meta.fields[i]) catch |err| {
                for (0..i) |j|
                    fs[j].deinit(gpa);
                return err;
            };
        }
        return .{
            .meta = meta,
            .fields = fs,
        };
    }

    pub fn deinit(self: *const Self, gpa: mem.Allocator) void {
        for (self.fields) |*f|
            f.deinit(gpa);
        gpa.free(self.fields);
    }

    pub fn append(self: *Self, gpa: mem.Allocator, value: anytype) !void {
        const T = @TypeOf(value);
        const ti = @typeInfo(T);
        assert(ti == .@"struct");
        const field_count = ti.@"struct".fields.len;
        assert(field_count == self.fields.len);

        var extracted: [field_count][]const u8 = undefined;
        self.meta.extractRaw(T, &value, &extracted);

        try self.appendRaw(gpa, &extracted);
    }

    pub fn appendRaw(self: *Self, gpa: mem.Allocator, data: []const []const u8) !void {
        assert(data.len == self.fields.len);
        for (self.fields, data, 0..) |*f, d, i| {
            f.appendBytes(gpa, d) catch |err| {
                for (0..i) |j|
                    self.fields[j].pop();
                return err;
            };
        }
    }

    pub fn appendBytes(self: *Self, gpa: mem.Allocator, bytes: []const u8) !void {
        const expected_len = self.meta.size();
        assert(bytes.len == expected_len);

        const before_size = self.len();
        errdefer self.setSize(before_size);

        var idx: usize = 0;
        for (self.fields) |*f| {
            const size = f.meta.size;
            try f.appendBytes(gpa, bytes[idx .. idx + size]);
            idx += size;
        }
        assert(idx == expected_len);
    }

    pub fn remove(self: *Self, index: usize) void {
        assert(index < self.len());
        for (self.fields) |*f| f.remove(index);
    }

    pub fn pop(self: *Self) void {
        const n = self.len();
        if (n == 0) return;
        self.remove(n - 1);
    }

    pub fn len(self: *const Self) usize {
        if (self.fields.len == 0) return 0;
        const l = self.fields[0].len();
        for (self.fields[1..]) |f|
            assert(f.len() == l);
        return l;
    }

    pub fn setSize(self: *Self, size: usize) void {
        for (self.fields) |*f|
            f.setSize(size);
    }
};

test "MultiField.Meta.from" {
    const C1 = struct {
        pub const cid = 1;
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
        MultiField.Meta.from(C1).*,
    );
    const C2 = struct {
        a: u8,
        b: u32,
        c: u16,
    };
    try testing.expectEqualDeep(
        MultiField.Meta{
            .cid = util.hashTypeName(C2),
            .fields = ([_]Field.Meta{
                Field.Meta{ .index = 0, .name = "a", .size = 1, .alignment = 1 },
                Field.Meta{ .index = 1, .name = "b", .size = 4, .alignment = 4 },
                Field.Meta{ .index = 2, .name = "c", .size = 2, .alignment = 2 },
            })[0..],
        },
        MultiField.Meta.from(C2).*,
    );
}

test "MultiField.Meta.extract" {
    const C = struct {
        x: u32,
        y: u32,
    };
    const meta: MultiField.Meta = MultiField.Meta.from(C).*;
    var extracted: [2][]const u8 = undefined;
    meta.extractRaw(C, &C{
        .x = 10,
        .y = 20,
    }, &extracted);
    try testing.expectEqual(
        @as(u32, 10),
        mem.bytesAsValue(u32, extracted[0]).*,
    );
    try testing.expectEqual(
        @as(u32, 20),
        mem.bytesAsValue(u32, extracted[1]).*,
    );
}

test "MultiField.Meta.extractBytes" {
    const C = struct {
        x: u32,
        y: u16,
        z: u8,
    };
    const meta: MultiField.Meta = MultiField.Meta.from(C).*;
    try testing.expectEqual(@as(usize, 7), meta.size());

    var out: [meta.size()]u8 = undefined;
    meta.extractBytes(C, &C{
        .x = 0x11223344,
        .y = 0x5566,
        .z = 0x77,
    }, out[0..]);

    const x = mem.bytesAsValue(u32, out[0..@sizeOf(u32)]).*;
    const y = mem.bytesAsValue(u16, out[@sizeOf(u32) .. @sizeOf(u32) + @sizeOf(u16)]).*;
    const z = mem.bytesAsValue(u8, out[@sizeOf(u32) + @sizeOf(u16) .. @sizeOf(u32) + @sizeOf(u16) + @sizeOf(u8)]).*;
    try testing.expectEqual(@as(u32, 0x11223344), x);
    try testing.expectEqual(@as(u16, 0x5566), y);
    try testing.expectEqual(@as(u8, 0x77), z);
}

test "MultiField.appendRaw" {
    const alloc = testing.allocator;
    const C = struct {
        x: u32,
        y: u32,
    };
    var multi = try MultiField.init(alloc, MultiField.Meta.from(C));
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

test "MultiField.appendBytes" {
    const alloc = testing.allocator;
    const C = struct {
        x: u32,
        y: u16,
        z: u8,
    };
    const meta: MultiField.Meta = MultiField.Meta.from(C).*;
    var multi = try MultiField.init(alloc, &meta);
    defer multi.deinit(alloc);

    const value = C{
        .x = 0x11223344,
        .y = 0x5566,
        .z = 0x77,
    };
    var bytes: [meta.size()]u8 = undefined;
    meta.extractBytes(C, &value, bytes[0..]);

    try multi.appendBytes(alloc, bytes[0..]);
    try testing.expectEqual(@as(usize, 1), multi.len());
    try testing.expectEqual(
        @as(u32, 0x11223344),
        mem.bytesAsValue(u32, multi.fields[0].atRaw(0)).*,
    );
    try testing.expectEqual(
        @as(u16, 0x5566),
        mem.bytesAsValue(u16, multi.fields[1].atRaw(0)).*,
    );
    try testing.expectEqual(
        @as(u8, 0x77),
        mem.bytesAsValue(u8, multi.fields[2].atRaw(0)).*,
    );
}

test "MultiField.append" {
    const alloc = testing.allocator;
    const C = struct {
        x: u32,
        y: u32,
    };
    var multi = try MultiField.init(alloc, MultiField.Meta.from(C));
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

const util = @import("util.zig");
const Field = @import("field.zig").Field;
