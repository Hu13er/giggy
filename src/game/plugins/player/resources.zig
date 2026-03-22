pub const Player = struct {
    entity: ecs.Entity,
};

pub const SyncMap = struct {
    map: std.AutoArrayHashMap(ecs.Entity, ecs.Entity),

    pub fn init(gpa: mem.Allocator) @This() {
        return .{
            .map = .init(gpa),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.map.deinit();
    }
};

const std = @import("std");
const mem = std.mem;
const engine = @import("engine");
const ecs = engine.ecs;
