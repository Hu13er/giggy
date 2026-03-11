pub const util = @import("util.zig");
pub const field = @import("field.zig");
pub const multi_field = @import("multi_field.zig");
pub const archetype = @import("archetype.zig");
pub const world = @import("world.zig");
pub const command_buffer = @import("command_buffer.zig");
pub const registry = @import("registry.zig");

pub const Field = field.Field;
pub const MultiField = multi_field.MultiField;
pub const Archetype = archetype.Archetype;
pub const Entity = archetype.Entity;
pub const CommandBuffer = command_buffer.CommandBuffer;
pub const World = world.World;
pub const ComponentRegistry = registry.ComponentRegistry;

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
