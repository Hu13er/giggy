pub const Plugin = @import("plugin.zig").Plugin;
pub const resources = @import("resources.zig");
pub const systems = @import("systems.zig");
pub const wire = @import("wire.zig");

pub const enet = @cImport({
    @cInclude("enet.h");
});

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const builtin = @import("builtin");
