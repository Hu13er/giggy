pub fn writeArchetypeRow(writer: anytype, archetype: *const ecs.Archetype, row: usize) (Error || @TypeOf(writer).Error)!void {
    var it = archetype.rowIter(row);
    while (it.next()) |field| {
        try writeField(writer, field.field_meta, field.bytes);
    }
}

pub fn readArchetypeRow(reader: anytype, archetype: *ecs.Archetype, row: usize) (Error || @TypeOf(reader).NoEofError)!void {
    var it = archetype.rowIter(row);
    while (it.next()) |field| {
        try readField(reader, field.field_meta, field.bytes);
    }
}

fn writeField(writer: anytype, meta: *const ecs.Field.Meta, bytes: []const u8) (Error || @TypeOf(writer).Error)!void {
    if (!meta.type.isWireScalar()) return error.UnsupportedFieldType;
    switch (meta.type.tag) {
        .bool => {
            if (bytes.len != 1) return error.UnsupportedBitSize;
            try writer.writeByte(if (bytes[0] != 0) 1 else 0);
        },
        .int => try writeInt(writer, true, meta.size, bytes),
        .uint => try writeInt(writer, false, meta.size, bytes),
        .float => try writeFloat(writer, meta.size, bytes),
        else => return error.UnsupportedFieldType,
    }
}

fn readField(reader: anytype, meta: *const ecs.Field.Meta, bytes: []u8) (Error || @TypeOf(reader).NoEofError)!void {
    if (!meta.type.isWireScalar()) return error.UnsupportedFieldType;
    switch (meta.type.tag) {
        .bool => {
            if (bytes.len != 1) return error.UnsupportedBitSize;
            const b = try reader.readByte();
            if (b > 1) return error.InvalidBool;
            bytes[0] = b;
        },
        .int => try readInt(reader, true, meta.size, bytes),
        .uint => try readInt(reader, false, meta.size, bytes),
        .float => try readFloat(reader, meta.size, bytes),
        else => return error.UnsupportedFieldType,
    }
}

fn writeInt(writer: anytype, signed: bool, size: usize, bytes: []const u8) (Error || @TypeOf(writer).Error)!void {
    switch (size) {
        1 => if (signed) {
            const v = std.mem.bytesAsValue(i8, bytes).*;
            try writer.writeInt(i8, v, .little);
        } else {
            const v = bytes[0];
            try writer.writeInt(u8, v, .little);
        },
        2 => if (signed) {
            const v = std.mem.bytesAsValue(i16, bytes).*;
            try writer.writeInt(i16, v, .little);
        } else {
            const v = std.mem.bytesAsValue(u16, bytes).*;
            try writer.writeInt(u16, v, .little);
        },
        4 => if (signed) {
            const v = std.mem.bytesAsValue(i32, bytes).*;
            try writer.writeInt(i32, v, .little);
        } else {
            const v = std.mem.bytesAsValue(u32, bytes).*;
            try writer.writeInt(u32, v, .little);
        },
        8 => if (signed) {
            const v = std.mem.bytesAsValue(i64, bytes).*;
            try writer.writeInt(i64, v, .little);
        } else {
            const v = std.mem.bytesAsValue(u64, bytes).*;
            try writer.writeInt(u64, v, .little);
        },
        else => return error.UnsupportedBitSize,
    }
}

fn readInt(reader: anytype, signed: bool, size: usize, bytes: []u8) (Error || @TypeOf(reader).NoEofError)!void {
    switch (size) {
        1 => if (signed) {
            const v = try reader.readInt(i8, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.readInt(u8, .little);
            bytes[0] = v;
        },
        2 => if (signed) {
            const v = try reader.readInt(i16, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.readInt(u16, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        4 => if (signed) {
            const v = try reader.readInt(i32, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.readInt(u32, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        8 => if (signed) {
            const v = try reader.readInt(i64, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.readInt(u64, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        else => return error.UnsupportedBitSize,
    }
}

fn writeFloat(writer: anytype, size: usize, bytes: []const u8) (Error || @TypeOf(writer).Error)!void {
    switch (size) {
        2 => {
            const v = std.mem.bytesAsValue(f16, bytes).*;
            const bits: u16 = @bitCast(v);
            try writer.writeInt(u16, bits, .little);
        },
        4 => {
            const v = std.mem.bytesAsValue(f32, bytes).*;
            const bits: u32 = @bitCast(v);
            try writer.writeInt(u32, bits, .little);
        },
        8 => {
            const v = std.mem.bytesAsValue(f64, bytes).*;
            const bits: u64 = @bitCast(v);
            try writer.writeInt(u64, bits, .little);
        },
        else => return error.UnsupportedBitSize,
    }
}

fn readFloat(reader: anytype, size: usize, bytes: []u8) (Error || @TypeOf(reader).NoEofError)!void {
    switch (size) {
        2 => {
            const bits = try reader.readInt(u16, .little);
            const v: f16 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        4 => {
            const bits = try reader.readInt(u32, .little);
            const v: f32 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        8 => {
            const bits = try reader.readInt(u64, .little);
            const v: f64 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        else => return error.UnsupportedBitSize,
    }
}

pub const Error = error{
    UnsupportedFieldType,
    UnsupportedBitSize,
    InvalidBool,
};

test "wire archetype row roundtrip" {
    const alloc = testing.allocator;

    const Pos = struct {
        pub const cid = 1;
        x: f32,
        y: f32,
    };
    const Flags = struct {
        pub const cid = 2;
        alive: bool,
        team: u8,
    };

    const meta: ecs.Archetype.StaticMeta = .from(&[_]type{ Pos, Flags });
    var arch = try ecs.Archetype.init(alloc, meta);
    defer arch.deinit(alloc);

    try arch.append(alloc, 1, .{
        Pos{ .x = 1.25, .y = -2.5 },
        Flags{ .alive = true, .team = 3 },
    });

    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try writeArchetypeRow(stream.writer(), &arch, 0);

    var new_arch = try ecs.Archetype.init(alloc, meta);
    defer new_arch.deinit(alloc);
    try new_arch.append(alloc, 2, .{
        Pos{ .x = 0, .y = 0 },
        Flags{ .alive = false, .team = 0 },
    });

    stream = std.io.fixedBufferStream(stream.getWritten());
    try readArchetypeRow(stream.reader(), &new_arch, 0);

    const pos = new_arch.atAuto(Pos, 0);
    const flags = new_arch.atAuto(Flags, 0);
    try testing.expectEqual(@as(f32, 1.25), pos.x.*);
    try testing.expectEqual(@as(f32, -2.5), pos.y.*);
    try testing.expectEqual(true, flags.alive.*);
    try testing.expectEqual(@as(u8, 3), flags.team.*);
}

const std = @import("std");
const testing = std.testing;

const engine = @import("engine");
const ecs = engine.ecs;
