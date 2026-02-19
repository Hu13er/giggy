pub const RoomManager = struct {
    current: ?u32,
    bounds: std.AutoHashMap(u32, RoomBounds),
    grids: std.AutoHashMap(u32, Grid),
    gpa: mem.Allocator,

    const Self = @This();
    pub const cell_size: f32 = 32.0;

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .current = null,
            .bounds = std.AutoHashMap(u32, RoomBounds).init(gpa),
            .grids = std.AutoHashMap(u32, Grid).init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bounds.deinit();
        var it = self.grids.valueIterator();
        while (it.next()) |g| g.deinit(self.gpa);
        self.grids.deinit();
    }

    pub fn setBounds(self: *Self, room_id: u32, bounds: RoomBounds) !void {
        try self.bounds.put(room_id, bounds);
        errdefer _ = self.bounds.remove(room_id);

        if (self.grids.getPtr(room_id)) |g| g.deinit(self.gpa);
        const grid = try Grid.init(self.gpa, bounds, cell_size);
        errdefer grid.deinit(self.gpa);
        try self.grids.put(room_id, grid);
    }

    pub fn getBounds(self: *Self, room_id: u32) ?RoomBounds {
        return self.bounds.get(room_id);
    }

    pub fn getGrid(self: *Self, room_id: u32) ?Grid {
        return self.grids.get(room_id);
    }
};

pub fn roomIdFromName(name: []const u8) u32 {
    var hash = std.hash.Wyhash.init(0);
    hash.update(name);
    return @truncate(hash.final());
}

pub fn roomFromName(name: []const u8) components.world.Room {
    return .{ .id = roomIdFromName(name) };
}

pub const RoomBounds = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const Grid = struct {
    w: usize,
    h: usize,
    walkables: []bool,

    pub fn init(gpa: mem.Allocator, bounds: RoomBounds, cell_size: f32) !@This() {
        const w: usize = @intFromFloat(bounds.w / cell_size);
        const h: usize = @intFromFloat(bounds.h / cell_size);
        const walkables = try gpa.alloc(bool, w * h);
        return .{ .w = w, .h = h, .walkables = walkables };
    }

    pub fn deinit(self: *const @This(), gpa: mem.Allocator) void {
        gpa.free(self.walkables);
    }
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const path_finding = engine.algo.path_finding;

const game = @import("game");
const components = game.components;
