const std = @import("std");
const math = @import("math.zig");
const heuristics = @import("path_finding_heuristics.zig");

pub const Vec2 = math.Vec2;
pub const GridPos = heuristics.GridPos;
pub const Heuristic = heuristics.Heuristic;

const Node = struct {
    pos: GridPos,
    g: u32 = 0,
    h: u32 = 0,
    parent: ?GridPos = null,

    fn f(self: Node) u32 {
        return self.g + self.h;
    }
};

const PQContext = struct {
    pub fn compare(_: PQContext, a: Node, b: Node) std.math.Order {
        const af = a.f();
        const bf = b.f();
        if (af < bf) return .lt;
        if (af > bf) return .gt;
        return .eq;
    }
};

const PQ = std.PriorityQueue(Node, PQContext, PQContext.compare);

/// Grid-based A* pathfinder that works in world space (`Vec2`).
///
/// - `cell_size` controls how many world units each grid cell spans.
/// - `grid` is a boolean array where `true` means walkable, `false` blocked.
pub const Pathfinder = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cell_size: f32,
    grid: []bool, // true = walkable
    heuristic: Heuristic,

    pub fn init(
        allocator: std.mem.Allocator,
        w: usize,
        h: usize,
        cell_size: f32,
        heuristic: Heuristic,
    ) !Pathfinder {
        return .{
            .allocator = allocator,
            .width = w,
            .height = h,
            .cell_size = cell_size,
            .grid = try allocator.alloc(bool, w * h),
            .heuristic = heuristic,
        };
    }

    pub fn initDefault(
        allocator: std.mem.Allocator,
        w: usize,
        h: usize,
        cell_size: f32,
    ) !Pathfinder {
        return Pathfinder.init(allocator, w, h, cell_size, .manhattan);
    }

    pub fn deinit(self: *Pathfinder) void {
        self.allocator.free(self.grid);
    }

    fn index(self: *const Pathfinder, p: GridPos) ?usize {
        if (p.x < 0 or p.y < 0) return null;
        const ux: usize = @intCast(p.x);
        const uy: usize = @intCast(p.y);
        if (ux >= self.width or uy >= self.height) return null;
        return uy * self.width + ux;
    }

    /// Convert world-space position to integer grid coordinates.
    fn toGrid(self: *const Pathfinder, world: Vec2) GridPos {
        return .{
            .x = @intFromFloat(world.x / self.cell_size),
            .y = @intFromFloat(world.y / self.cell_size),
        };
    }

    /// Convert integer grid coordinates to world position at the cell center.
    fn toWorld(self: *const Pathfinder, grid: GridPos) Vec2 {
        const gx: f32 = @floatFromInt(grid.x);
        const gy: f32 = @floatFromInt(grid.y);
        const offset = self.cell_size * 0.5;
        return .{
            .x = gx * self.cell_size + offset,
            .y = gy * self.cell_size + offset,
        };
    }

    pub fn setWalkable(self: *Pathfinder, world_pos: Vec2, walkable: bool) void {
        const p = self.toGrid(world_pos);
        const idx = self.index(p) orelse return;
        self.grid[idx] = walkable;
    }

    fn isWalkable(self: *const Pathfinder, p: GridPos) bool {
        const idx = self.index(p) orelse return false;
        return self.grid[idx];
    }

    /// Find a path between two world positions.
    ///
    /// Returns `null` if no path exists, otherwise a newly allocated slice of
    /// `Vec2` positions from start to end (inclusive). Caller owns the slice
    /// and must free it with the same allocator.
    pub fn findPath(self: *Pathfinder, start: Vec2, end: Vec2) !?[]Vec2 {
        const start_grid = self.toGrid(start);
        const end_grid = self.toGrid(end);

        if (!self.isWalkable(start_grid) or !self.isWalkable(end_grid)) return null;

        var open_set = PQ.init(self.allocator, .{});
        defer open_set.deinit();

        var visited = std.AutoHashMap(GridPos, u32).init(self.allocator);
        defer visited.deinit();

        var came_from = std.AutoHashMap(GridPos, GridPos).init(self.allocator);
        defer came_from.deinit();

        try open_set.add(.{
            .pos = start_grid,
            .g = 0,
            .h = heuristics.estimate(self.heuristic, start_grid, end_grid),
        });
        try visited.put(start_grid, 0);

        const directions = [_]GridPos{
            .{ .x = 0, .y = -1 },
            .{ .x = 0, .y = 1 },
            .{ .x = -1, .y = 0 },
            .{ .x = 1, .y = 0 },
        };

        while (open_set.count() > 0) {
            const current = open_set.remove();

            if (current.pos.x == end_grid.x and current.pos.y == end_grid.y) {
                return self.reconstructPath(came_from, current.pos);
            }

            for (directions) |dir| {
                const neighbor = GridPos{
                    .x = current.pos.x + dir.x,
                    .y = current.pos.y + dir.y,
                };

                if (!self.isWalkable(neighbor)) continue;

                const tentative_g = current.g + 1;

                if (visited.get(neighbor)) |existing_g| {
                    if (tentative_g >= existing_g) continue;
                }

                try visited.put(neighbor, tentative_g);
                try came_from.put(neighbor, current.pos);

                try open_set.add(.{
                    .pos = neighbor,
                    .g = tentative_g,
                    .h = heuristics.estimate(self.heuristic, neighbor, end_grid),
                });
            }
        }

        return null;
    }

    fn reconstructPath(
        self: *Pathfinder,
        came_from: std.AutoHashMap(GridPos, GridPos),
        end_grid: GridPos,
    ) !?[]Vec2 {
        // Count steps.
        var len: usize = 0;
        var current = end_grid;
        while (true) {
            len += 1;
            const parent = came_from.get(current) orelse break;
            current = parent;
        }

        // Allocate result slice.
        var path = try self.allocator.alloc(Vec2, len);

        // Fill backwards, converting grid positions back to world space.
        var i: usize = len - 1;
        current = end_grid;
        while (true) {
            path[i] = self.toWorld(current);
            if (i == 0) break;
            i -= 1;
            const parent = came_from.get(current) orelse break;
            current = parent;
        }

        return path;
    }
};

