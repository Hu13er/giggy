pub const Nid = Entity;

pub const NidRegistry = struct {
    nid_entity: std.AutoHashMap(Nid, Entity),
    entity_nid: std.AutoHashMap(Entity, Nid),

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .nid_entity = .init(gpa),
            .entity_nid = .init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.nid_entity.deinit();
        self.entity_nid.deinit();
    }

    pub fn register(self: *Self, entity: Entity, nid: Nid) !void {
        try self.nid_entity.put(nid, entity);
        errdefer _ = self.nid_entity.remove(nid);
        try self.entity_nid.put(entity, nid);
        errdefer _ = self.entity_nid.remove(entity);
    }

    pub fn entityOf(self: *const Self, nid: Nid) ?Nid {
        return self.nid_entity.get(nid);
    }

    pub fn nidOf(self: *const Self, entity: Entity) ?Entity {
        return self.entity_nid.get(entity);
    }

    pub fn removeEntity(self: *Self, entity: Entity) bool {
        const entry = self.entity_nid.fetchRemove(entity) orelse return false;
        const nid = entry.value;
        const removed = self.nid_entity.remove(nid);
        assert(removed);
        return true;
    }

    pub fn removeNid(self: *Self, nid: Nid) bool {
        const entry = self.nid_entity.fetchRemove(nid) orelse return false;
        const entity = entry.value;
        const removed = self.entity_nid.remove(entity);
        assert(removed);
        return true;
    }
};

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const engine = @import("engine");
const ecs = engine.ecs;
const Entity = ecs.Entity;
