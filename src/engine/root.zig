pub const core = @import("core/root.zig");
pub const ecs = @import("ecs/root.zig");
pub const assets = @import("assets/root.zig");
pub const math = @import("math/root.zig");
pub const graph = @import("graph/root.zig");
pub const prefabs = @import("prefabs/root.zig");
pub const raylib = @import("raylib/root.zig").raylib;
pub const raymath = @import("raylib/root.zig").raymath;
pub const path_finding = @import("path_finding.zig");

// run tests with:
// zig test --dep engine -Mengine=src/engine/root.zig -I third_party/raylib/include -isystem /usr/include/
test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
