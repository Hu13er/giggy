test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");

pub const RingBuffer = @import("ring_buffer.zig").RingBuffer;
