pub const BarResource = struct {
    current_perc: f32 = 1.0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
