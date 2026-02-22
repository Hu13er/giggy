pub fn isUnique(comptime T: type, items: []T) bool {
    if (items.len <= 1) return true;
    std.sort.block(T, items, {}, std.sort.asc(T));
    for (1..items.len) |i| {
        if (items[i - 1] == items[i]) return false;
    }
    return true;
}

test isUnique {
    var array0 = [_]u8{};
    try testing.expectEqual(true, isUnique(u8, &array0));
    var array1 = [_]u8{1};
    try testing.expectEqual(true, isUnique(u8, &array1));
    var array2 = [_]u8{ 1, 2, 3 };
    try testing.expectEqual(true, isUnique(u8, &array2));
    var array3 = [_]u8{ 3, 2, 3 };
    try testing.expectEqual(false, isUnique(u8, &array3));
}

pub fn typesOfBundle(comptime Bundle: type) []type {
    const ti = @typeInfo(Bundle);
    if (ti != .@"struct") @compileError("Bundle should be a struct");
    const fields = ti.@"struct".fields;
    var out: [fields.len]type = undefined;
    for (fields, 0..) |f, i|
        out[i] = f.type;
    return out[0..];
}

pub fn cidOf(comptime T: type) u32 {
    assertComponent(T);
    if (@hasDecl(T, "cid"))
        return T.cid;
    return hashTypeName(T);
}

pub fn hashTypeName(comptime T: type) u32 {
    const name = @typeName(T);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(name[0..]);
    return @truncate(hasher.final());
}

pub fn assertComponent(comptime T: type) void {
    comptime if (!isComponent(T)) @compileError("component is expected to be struct");
}

pub fn isComponent(comptime T: type) bool {
    const ti = @typeInfo(T);
    return ti == .@"struct";
}

pub fn isView(comptime View: type) bool {
    const ti = @typeInfo(View);
    if (ti != .@"struct") return false;
    if (!@hasDecl(View, "Of")) return false;
    return isComponent(View.Of);
}

pub fn assertView(comptime View: type) void {
    comptime if (!isView(View)) @compileError("invalid View type");
}

test isComponent {
    try testing.expectEqual(true, isComponent(struct {
        pub const cid = 1;
        a: f32,
    }));
    try testing.expectEqual(true, isComponent(struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    }));
    try testing.expectEqual(true, isComponent(struct {
        foo: f32,
    }));
    try testing.expectEqual(false, isComponent(u8));
}

pub fn isBundle(comptime Bundle: type) bool {
    const ti = @typeInfo(Bundle);
    return ti == .@"struct";
}

pub fn ViewOf(comptime C: type) type {
    const ti = @typeInfo(C);
    assert(ti == .@"struct");

    const fields = ti.@"struct".fields;

    var new_fields: [fields.len]std.builtin.Type.StructField = undefined;

    inline for (fields, 0..) |f, i| {
        new_fields[i] = .{
            .name = f.name,
            .type = *f.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(*f.type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &new_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

test ViewOf {
    const C1 = struct {
        pub const cid = 1;
        x: u32,
        y: u32,
    };
    const C1View = ViewOf(C1);
    var c: C1 = .{
        .x = 5,
        .y = 10,
    };
    const v: C1View = .{
        .x = &c.x,
        .y = &c.y,
    };
    try testing.expectEqual(c.x, v.x.*);
    try testing.expectEqual(c.y, v.y.*);
}

const std = @import("std");
const meta = std.meta;
const testing = std.testing;
const assert = std.debug.assert;
