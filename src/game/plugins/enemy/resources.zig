pub const ChasePath = struct {
    paths: std.AutoHashMap(ecs.Entity, Path),
    gpa: mem.Allocator,

    pub const Path = struct {
        points: ?[]xmath.Vec2,
        head: usize,
        tick: u32,
    };

    const Self = @This();

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .paths = .init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.paths.deinit();
    }

    pub fn update(self: *Self, entity: ecs.Entity, tick: u32, points: ?[]xmath.Vec2) !*Path {
        const owned = if (points) |ps|
            try self.gpa.dupe(xmath.Vec2, ps)
        else
            null;
        errdefer if (owned) |ps| self.gpa.free(ps);

        if (self.paths.getPtr(entity)) |ptr| {
            if (ptr.*.points) |ps| self.gpa.free(ps);
            ptr.*.head = 0;
            ptr.*.tick = tick;
            ptr.*.points = owned;
            return ptr;
        } else {
            try self.paths.put(entity, Path{
                .head = 0,
                .tick = tick,
                .points = owned,
            });
            return self.paths.getPtr(entity).?;
        }
    }

    pub fn remove(self: *Self, entity: ecs.Entity) bool {
        const ptr = self.paths.getPtr(entity) orelse return false;
        self.gpa.free(ptr.*.points);
        const removed = self.paths.remove(entity);
        assert(removed);
        return true;
    }
};

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const engine = @import("engine");
const ecs = engine.ecs;
const xmath = engine.math;
