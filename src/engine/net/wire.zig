// Protocol:
//
// [N: u8 - Num of Archetypes]
// [M-0: u8 - Num of components] [CID-0: u32] ... [CID-M-0]
// ...
// [M-N: u8 - Num of components] ...
// [K: u16 - Num of entities]
// [I-0: u8 - Archetype index] [Entity-0: u32 - Entity ID] [Comp-0] ...
// ...
// [I-K: u8 - Archetype index] [Entity-0: u32 - Entity ID] [Comp-0] ...
//
// Note: Assumes CIDs are sorted

pub const ProtocolWriter = struct {
    entities: EntityList,
    archetypes: ArchetypeSet,
    gpa: mem.Allocator,

    const Self = @This();

    const ArchetypeSet = std.AutoArrayHashMap(*const ecs.Archetype, void);

    const EntityList = std.ArrayList(Entity);
    const Entity = struct {
        archetype: *const ecs.Archetype,
        row: usize,
    };

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .entities = .empty,
            .archetypes = .init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.gpa);
        self.archetypes.deinit();
    }

    pub fn push(self: *Self, archetype: *const ecs.Archetype, row: usize) !void {
        try self.entities.append(self.gpa, .{
            .archetype = archetype,
            .row = row,
        });
        errdefer _ = self.entities.pop();
        try self.archetypes.put(archetype, {});
    }

    pub fn flush(self: *Self, writer: *Writer) !void {
        if (self.archetypes.count() > std.math.maxInt(u8))
            return Error.TooManyArchetypes;
        if (self.entities.items.len > std.math.maxInt(u16))
            return Error.TooManyEntities;

        const archs = self.archetypes.keys();
        try writer.writeInt(u8, @intCast(archs.len), .little);
        for (archs) |a| {
            try writer.writeInt(u8, @intCast(a.components.len), .little);
            for (a.components) |c|
                try writer.writeInt(u32, c.meta.cid, .little);
        }

        try writer.writeInt(u16, @intCast(self.entities.items.len), .little);
        for (self.entities.items) |e| {
            const idx: usize = for (archs, 0..) |a, i| {
                if (a == e.archetype) break i;
            } else unreachable;
            try writer.writeInt(u8, @intCast(idx), .little);
            const entity = e.archetype.entities.items[e.row];
            try writer.writeInt(u32, entity, .little);
            try writeArchetypeRow(writer, e.archetype, e.row);
        }

        self.entities.clearRetainingCapacity();
        self.archetypes.clearRetainingCapacity();
    }

    fn writeArchetypeRow(writer: anytype, archetype: *const ecs.Archetype, row: usize) !void {
        var it = archetype.rowIter(row);
        while (it.next()) |field| {
            try writeField(writer, field.field_meta, field.bytes);
        }
    }

    fn writeField(writer: anytype, meta: *const ecs.Field.Meta, bytes: []const u8) !void {
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
};

pub const ProtocolReader = struct {
    registry: *const ecs.registry.ComponentRegistry,

    const Self = @This();

    pub fn init(registry: *const ecs.registry.ComponentRegistry) Self {
        return .{
            .registry = registry,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn store(self: *Self, world: *ecs.World, reader: *Reader) !void {
        const n_arch = try reader.takeInt(u8, .little);
        var arch_metas_buffer: [std.math.maxInt(u8)]ecs.Archetype.StaticMeta = undefined;
        var arch_metas = std.ArrayList(ecs.Archetype.StaticMeta).initBuffer(arch_metas_buffer[0..]);
        for (0..n_arch) |_| {
            const m_cids = try reader.takeInt(u8, .little);

            var comps_buffer: [std.math.maxInt(u8)]*const ecs.MultiField.Meta = undefined;
            var comps = std.ArrayList(*const ecs.MultiField.Meta).initBuffer(comps_buffer[0..]);
            for (0..m_cids) |_| {
                const cid = try reader.takeInt(u32, .little);
                const meta = self.registry.getByCidOrNull(cid) orelse return Error.UnknownComponent;

                comps.appendAssumeCapacity(meta);
            }

            const meta = try ecs.Archetype.OwnedMeta.init(comps.items);
            arch_metas.appendAssumeCapacity(meta.view());
        }

        const k_entities = try reader.takeInt(u16, .little);
        for (0..k_entities) |_| {
            const idx = try reader.takeInt(u8, .little);
            const e = try reader.takeInt(u32, .little);
            _ = world.despawn(e);

            // TODO: we are abusing StaticMeta here.
            // it already works since world.spawn* copies memory.
            // but StaticMeta suggests that it has static lifetime

            const entry = try world.spawnUndefined(e, &arch_metas.items[idx]);
            try readArchetypeRow(reader, entry.archetype, entry.row);
        }
    }

    fn readArchetypeRow(reader: *Reader, archetype: *ecs.Archetype, row: usize) !void {
        var it = archetype.rowIter(row);
        while (it.next()) |field| {
            try readField(reader, field.field_meta, field.bytes);
        }
    }

    fn readField(reader: *Reader, meta: *const ecs.Field.Meta, bytes: []u8) !void {
        if (!meta.type.isWireScalar()) return error.UnsupportedFieldType;
        switch (meta.type.tag) {
            .bool => {
                if (bytes.len != 1) return error.UnsupportedBitSize;
                const b = try reader.takeByte();
                if (b > 1) return error.InvalidBool;
                bytes[0] = b;
            },
            .int => try readInt(reader, true, meta.size, bytes),
            .uint => try readInt(reader, false, meta.size, bytes),
            .float => try readFloat(reader, meta.size, bytes),
            else => return error.UnsupportedFieldType,
        }
    }
};

fn writeInt(writer: *Writer, signed: bool, size: usize, bytes: []const u8) !void {
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

fn readInt(reader: *Reader, signed: bool, size: usize, bytes: []u8) !void {
    switch (size) {
        1 => if (signed) {
            const v = try reader.takeInt(i8, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.takeInt(u8, .little);
            bytes[0] = v;
        },
        2 => if (signed) {
            const v = try reader.takeInt(i16, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.takeInt(u16, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        4 => if (signed) {
            const v = try reader.takeInt(i32, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.takeInt(u32, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        8 => if (signed) {
            const v = try reader.takeInt(i64, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        } else {
            const v = try reader.takeInt(u64, .little);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        else => return error.UnsupportedBitSize,
    }
}

fn writeFloat(writer: *Writer, size: usize, bytes: []const u8) !void {
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

fn readFloat(reader: *Reader, size: usize, bytes: []u8) !void {
    switch (size) {
        2 => {
            const bits = try reader.takeInt(u16, .little);
            const v: f16 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        4 => {
            const bits = try reader.takeInt(u32, .little);
            const v: f32 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        8 => {
            const bits = try reader.takeInt(u64, .little);
            const v: f64 = @bitCast(bits);
            @memcpy(bytes, std.mem.asBytes(&v));
        },
        else => return error.UnsupportedBitSize,
    }
}

pub const Error = error{
    TooManyArchetypes,
    TooManyEntities,
    UnknownComponent,
    UnsupportedFieldType,
    UnsupportedBitSize,
    InvalidBool,
};

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Writer = std.io.Writer;
const Reader = std.io.Reader;

const engine = @import("engine");
const ecs = engine.ecs;
