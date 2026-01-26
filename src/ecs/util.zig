pub fn typesOfTuple(tuple: anytype) []type {
    if (!isTuple(tuple))
        @compileError("input must be a tuple");
    const fields = meta.fields(@TypeOf(tuple));
    var out: [fields.len]type = undefined;
    for (fields, 0..) |f, i|
        out[i] = f.type;
    return out[0..];
}

pub fn typesFromTuple(tuple: anytype) []type {
    if (!isTuple(tuple))
        @compileError("input must be a tuple");
    const fields = meta.fields(@TypeOf(tuple));
    var out: [fields.len]type = undefined;
    for (fields, 0..) |f, i|
        out[i] = @field(tuple, f.name);
    return out[0..];
}

pub fn isComponent(T: type) bool {
    const ti = @typeInfo(T);
    if (ti != .@"struct") return false;
    return @hasDecl(T, "cid");
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
    try testing.expectEqual(false, isComponent(u8));
    try testing.expectEqual(false, isComponent(struct {
        foo: f32,
    }));
}

pub fn isTuple(arg: anytype) bool {
    const ti = @typeInfo(@TypeOf(arg));
    if (ti != .@"struct") return false;
    return ti.@"struct".is_tuple;
}

test isTuple {
    try testing.expectEqual(true, isTuple(.{@as(u8, 10)}));
    try testing.expectEqual(true, isTuple(.{u8}));
    try testing.expectEqual(true, isTuple(.{ u8, u16 }));
    try testing.expectEqual(false, isTuple(@as(u8, 10)));
    try testing.expectEqual(false, isTuple(u8));

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
    try testing.expectEqual(true, isTuple(.{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 1 },
    }));
}

pub fn ViewOf(comptime T: type) type {
    const ti = @typeInfo(T);
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
