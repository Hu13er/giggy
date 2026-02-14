pub const util = @import("./ecs/util.zig");
pub const field = @import("./ecs/field.zig");
pub const multi_field = @import("./ecs/multi_field.zig");
pub const archetype = @import("./ecs/archetype.zig");
pub const world = @import("./ecs/world.zig");
pub const command_buffer = @import("./ecs/command_buffer.zig");

pub const Field = field.Field;
pub const MultiField = multi_field.MultiField;
pub const Archetype = archetype.Archetype;
pub const Entity = archetype.Entity;
pub const CommandBuffer = command_buffer.CommandBuffer;
pub const World = world.World;

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
