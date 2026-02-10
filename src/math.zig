pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn normalize(self: Vec2) Vec2 {
        const a = self.abs();
        if (a < 0.01) return self;
        return .{ .x = self.x / a, .y = self.y / a };
    }

    pub fn dot(self: Vec2, b: Vec2) f32 {
        return self.x * b.x + self.y * b.y;
    }

    pub fn abs(self: Vec2) f32 {
        const sq = self.dot(self);
        return math.sqrt(sq);
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }
};

pub fn clamp01(v: anytype) @TypeOf(v) {
    return @max(@min(v, 1), 0);
}

const std = @import("std");
const math = std.math;
