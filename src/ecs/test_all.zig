/// Run all ECS module tests in one place.
const std = @import("std");

pub fn main() void {}

test "ecs suite" {
    _ = @import("archetype.zig");
    _ = @import("command_buffer.zig");
    _ = @import("world.zig");
    _ = @import("field.zig");
    _ = @import("multi_field.zig");
    _ = @import("util.zig");
}
