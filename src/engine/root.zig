pub const core = @import("core.zig");
pub const ecs = @import("ecs.zig");
pub const assets = @import("assets.zig");
pub const math = @import("math.zig");
pub const prefabs = @import("prefabs.zig");
pub const rl = @import("rl.zig").rl;
pub const rm = @import("rl.zig").rm;

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
