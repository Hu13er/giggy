pub const enet = @cImport({
    @cInclude("enet.h");
});

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
