pub const Field = struct {
    meta: Meta,
    buffer: Buffer,

    const Self = @This();

    const Buffer = std.ArrayListAligned(u8, max_alignment);
    const max_alignment = mem.Alignment.@"64";

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

    pub fn init(gpa: mem.Allocator, meta: Meta) !Self {
        assert(meta.alignment <= max_alignment.toByteUnits());
        return .{
            .meta = meta,
            .buffer = try Buffer.initCapacity(gpa, 1),
        };
    }

    pub fn deinit(self: *Self, gpa: mem.Allocator) void {
        self.buffer.deinit(gpa);
    }

    pub fn append(self: *Self, gpa: mem.Allocator, value: anytype) !void {
        const T = @TypeOf(value);
        assert(@sizeOf(T) == self.meta.size);
        try self.appendBytes(gpa, mem.asBytes(&value));
    }

    pub fn appendBytes(self: *Self, gpa: mem.Allocator, data: []const u8) !void {
        assert(data.len == self.meta.size);
        try self.buffer.appendSlice(gpa, data);
    }

    // remove `index` from field
    // Assums that @mod(buffer.items.len, self.meta.size) == 0
    pub fn remove(self: *Self, index: usize) void {
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

    pub fn pop(self: *Self) void {
        self.remove(self.len() - 1);
    }

    pub fn len(self: *const Self) usize {
        return self.buffer.items.len / self.meta.size;
    }

    pub fn setSize(self: *Self, size: usize) void {
        const new_len = size * self.meta.size;
        assert(new_len <= self.buffer.items.len);
        self.buffer.items.len = size * self.meta.size;
    }

    pub inline fn at(self: *const Self, comptime T: type, index: usize) *T {
        return @alignCast(mem.bytesAsValue(T, self.atRaw(index)));
    }

    pub inline fn atRaw(self: *const Self, index: usize) []u8 {
        const start = index * self.meta.size;
        return self.buffer.items[start .. start + self.meta.size];
    }
};

test "Field.Meta.fromScalar" {
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
}

test "Field.Meta.fromStruct" {
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

test "Field.appendBytes" {
    const alloc = testing.allocator;

    var f1 = try Field.init(alloc, .fromScalar(u8));
    defer f1.deinit(alloc);
    try f1.appendBytes(alloc, &[_]u8{0x88});
    try testing.expectEqual(@as(u8, 0x88), mem.bytesAsValue(u8, f1.atRaw(0)).*);

    var f2 = try Field.init(alloc, .fromScalar(u32));
    defer f2.deinit(alloc);
    const test_cases = [_]u32{
        0x00000000,
        0xDEADBEEF,
        0xCAFE8808,
        0xFFFFFFFF,
    };
    for (test_cases) |tc| {
        try f2.appendBytes(alloc, mem.asBytes(&tc));
    }
    for (test_cases, 0..) |expected, idx| {
        const actual_bytes = f2.atRaw(idx);
        try testing.expectEqual(expected, mem.bytesAsValue(u32, actual_bytes).*);
    }
}

test "Field.append" {
    const alloc = testing.allocator;

    var f1 = try Field.init(alloc, .fromScalar(u8));
    defer f1.deinit(alloc);
    try f1.append(alloc, @as(u8, 0x88));
    try testing.expectEqual(@as(u8, 0x88), mem.bytesAsValue(u8, f1.atRaw(0)).*);

    var f2 = try Field.init(alloc, .fromScalar(u32));
    defer f2.deinit(alloc);
    const test_cases = [_]u32{
        0x00000000,
        0xDEADBEEF,
        0xCAFE8808,
        0xFFFFFFFF,
    };
    for (test_cases) |tc| {
        try f2.append(alloc, tc);
    }
    for (test_cases, 0..) |expected, idx| {
        const actual_bytes = f2.atRaw(idx);
        try testing.expectEqual(expected, mem.bytesAsValue(u32, actual_bytes).*);
    }
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
