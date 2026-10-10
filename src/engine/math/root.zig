pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, b: Vec2) Vec2 {
        return .{ .x = self.x + b.x, .y = self.y + b.y };
    }

    pub fn sub(self: Vec2, b: Vec2) Vec2 {
        return self.add(b.neg());
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }

    pub fn neg(self: Vec2) Vec2 {
        return self.scale(-1);
    }

    pub fn normalize(self: Vec2) Vec2 {
        const a = self.abs();
        if (a < 0.001) return self;
        return .{ .x = self.x / a, .y = self.y / a };
    }

    pub fn dot(self: Vec2, b: Vec2) f32 {
        return self.x * b.x + self.y * b.y;
    }

    pub fn abs(self: Vec2) f32 {
        const sq = self.dot(self);
        return math.sqrt(sq);
    }

    pub fn ortho(self: Vec2) Vec2 {
        return .{ .x = -self.y, .y = self.x };
    }

    pub fn asRl(self: Vec2) rl.Vector2 {
        return .{ .x = self.x, .y = self.y };
    }
};

pub fn clamp01(v: anytype) @TypeOf(v) {
    return @max(@min(v, 1), 0);
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn wrapAngleDeg(angle: f32) f32 {
    var a = angle;
    while (a > 180.0) a -= 360.0;
    while (a < -180.0) a += 360.0;
    return a;
}

pub fn lerpAngleDeg(a: f32, b: f32, t: f32) f32 {
    return a + wrapAngleDeg(b - a) * t;
}

pub fn pushFromLine(c: Vec2, a: Vec2, b: Vec2, radius: f32) Vec2 {
    const ab = b.sub(a);
    const ab_len2 = ab.dot(ab);

    const t = clamp01(c.sub(a).dot(ab) / ab_len2);
    const delta = c.sub(a.add(ab.scale(t)));
    const dist = delta.abs();
    if (dist >= radius) return .{ .x = 0, .y = 0 };

    var n = delta.normalize();
    return n.scale(radius - dist);
}

pub fn nearestPointOnCircle(
    center: Vec2,
    radius: f32,
    point: Vec2,
) Vec2 {
    const dir = point.sub(center);
    const len = dir.abs();
    if (len <= 0.1) {
        return .{ .x = center.x + radius, .y = center.y };
    }
    return center.add(dir.normalize().scale(radius));
}

const std = @import("std");
const math = std.math;
const engine = @import("engine");
const rl = engine.raylib;

test {
    _ = std.testing.refAllDecls(@This());
}
