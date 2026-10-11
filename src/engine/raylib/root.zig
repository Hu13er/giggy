pub const raylib = @import("raylib_c");
pub const raymath = @import("raymath_c");

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
