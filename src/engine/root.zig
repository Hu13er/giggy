pub const algo = @import("algo/root.zig");
pub const assets = @import("assets/root.zig");
pub const container = @import("container/root.zig");
pub const core = @import("core/root.zig");
pub const ecs = @import("ecs/root.zig");
pub const graph = @import("graph/root.zig");
pub const math = @import("math/root.zig");
pub const net = @import("net/root.zig");
pub const prefabs = @import("prefabs/root.zig");
pub const raylib = @import("raylib/root.zig").raylib;
pub const raymath = @import("raylib/root.zig").raymath;

// run tests with:
// zig test --dep engine -Mengine=src/engine/root.zig -I third_party/raylib/include -I /third_party/enet/include -isystem /usr/include/
const std = @import("std");

test {
    _ = std.testing.refAllDecls(@This());
}
