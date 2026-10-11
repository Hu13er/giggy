pub const core = @import("core/root.zig");
pub const ecs = @import("ecs/root.zig");
pub const assets = @import("assets/root.zig");
pub const math = @import("math/root.zig");
pub const graph = @import("graph/root.zig");
pub const prefabs = @import("prefabs/root.zig");
pub const raylib = @import("raylib/root.zig").raylib;
pub const raymath = @import("raylib/root.zig").raymath;
pub const algo = @import("algo/root.zig");

// run tests with:
// zig build test-engine --summary all
test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
