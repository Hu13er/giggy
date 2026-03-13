pub const Plugin = @import("plugin.zig").Plugin;
pub const resources = @import("resources.zig");
pub const systems = @import("systems.zig");
pub const nid = @import("nid.zig");
pub const wire = @import("wire.zig");

pub const Sync = struct {};

pub const enet = @cImport({
    @cInclude("enet.h");
});

pub const ENetError = error{
    InitError,
    CreateHostError,
    InvalidAddress,
    ENetPeerSend,
};

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
