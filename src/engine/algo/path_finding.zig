const Node = struct {
    pos: GridPos,
    g: f32 = 0,
    h: f32 = 0,
    parent: ?GridPos = null,

    fn f(self: Node) f32 {
        return self.g + self.h;
    }
};

const pq_context = struct {
    pub fn compare(_: pq_context, a: Node, b: Node) std.math.Order {
        const af = a.f();
        const bf = b.f();
        if (af < bf) return .lt;
        if (af > bf) return .gt;
        return .eq;
    }
};

const PQ = std.PriorityQueue(Node, pq_context, pq_context.compare);

/// Grid-based A* pathfinder that works in world space (`Vec2`).
///
/// - `cell_size` controls how many world units each grid cell spans.
/// - `grid` is a boolean array where `true` means walkable, `false` blocked.
pub const Pathfinder = struct {
    width: usize,
    height: usize,
    cell_size: f32,
    grid: []bool, // true = walkable
    heuristic: Heuristic,
    directions: Directions,

    pub const Directions = []const GridPos;
    pub const principal_directions: Directions = &[_]GridPos{
        .{ .x = 0, .y = -1 }, // up
        .{ .x = 1, .y = 0 }, // right
        .{ .x = 0, .y = 1 }, // down
        .{ .x = -1, .y = 0 }, // left
    };

    pub const all_directions: Directions = &[_]GridPos{
        .{ .x = 0, .y = -1 }, // up
        .{ .x = 1, .y = 0 }, // right
        .{ .x = 0, .y = 1 }, // down
        .{ .x = -1, .y = 0 }, // left
        .{ .x = -1, .y = -1 }, // up-left
        .{ .x = 1, .y = -1 }, // up-right
        .{ .x = 1, .y = 1 }, // down-right
        .{ .x = -1, .y = 1 }, // down-left
    };

    pub fn init(
        w: usize,
        h: usize,
        cell_size: f32,
        grid: []bool,
        heuristic: Heuristic,
        directions: Directions,
    ) Pathfinder {
        return .{
            .width = w,
            .height = h,
            .cell_size = cell_size,
            .grid = grid,
            .heuristic = heuristic,
            .directions = directions,
        };
    }

    pub fn initDefault(
        w: usize,
        h: usize,
        cell_size: f32,
        grid: []bool,
    ) Pathfinder {
        return Pathfinder.init(w, h, cell_size, grid, .euclidean, all_directions);
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

    /// Find the nearest walkable cell to a world-space position within `max_radius` cells.
    /// Returns world-space position at the cell center, or null if none.
    pub fn nearestWalkableWorld(self: *const Pathfinder, world: Vec2, max_radius: i32) ?Vec2 {
        const max_x: i32 = @intCast(self.width);
        const max_y: i32 = @intCast(self.height);
        if (max_x == 0 or max_y == 0) return null;

        var start = self.toGrid(world);
        start.x = std.math.clamp(start.x, 0, max_x - 1);
        start.y = std.math.clamp(start.y, 0, max_y - 1);

        if (max_radius < 0) return null;
        const radius = std.math.clamp(max_radius, 0, if (max_x > max_y) max_x else max_y);

        const min_x = std.math.clamp(start.x - radius, 0, max_x - 1);
        const max_xr = std.math.clamp(start.x + radius, 0, max_x - 1);
        const min_y = std.math.clamp(start.y - radius, 0, max_y - 1);
        const max_yr = std.math.clamp(start.y + radius, 0, max_y - 1);

        var best_dist2: ?f32 = null;
        var best_pos: ?Vec2 = null;

        var y: i32 = min_y;
        while (y <= max_yr) : (y += 1) {
            var x: i32 = min_x;
            while (x <= max_xr) : (x += 1) {
                const p = GridPos{ .x = x, .y = y };
                if (!self.isWalkable(p)) continue;
                const world_p = self.toWorld(p);
                const dx = world_p.x - world.x;
                const dy = world_p.y - world.y;
                const dist2 = dx * dx + dy * dy;
                if (best_dist2 == null or dist2 < best_dist2.?) {
                    best_dist2 = dist2;
                    best_pos = world_p;
                }
            }
        }

        return best_pos;
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
    pub fn findPath(self: *Pathfinder, allocator: mem.Allocator, start: Vec2, end: Vec2) !?[]Vec2 {
        const start_grid = self.toGrid(start);
        const end_grid = self.toGrid(end);

        if (!self.isWalkable(start_grid) or !self.isWalkable(end_grid)) return null;

        var open_set = PQ.init(allocator, .{});
        defer open_set.deinit();

        var visited = std.AutoHashMap(GridPos, f32).init(allocator);
        defer visited.deinit();

        var came_from = std.AutoHashMap(GridPos, GridPos).init(allocator);
        defer came_from.deinit();

        try open_set.add(.{
            .pos = start_grid,
            .g = 0,
            .h = heuristics.estimate(self.heuristic, start_grid, end_grid),
        });
        try visited.put(start_grid, 0);

        while (open_set.count() > 0) {
            const current = open_set.remove();

            if (current.pos.x == end_grid.x and current.pos.y == end_grid.y) {
                return self.reconstructPath(allocator, came_from, current.pos);
            }

            for (self.directions) |dir| {
                const neighbor = GridPos{
                    .x = current.pos.x + dir.x,
                    .y = current.pos.y + dir.y,
                };

                if (!self.isWalkable(neighbor)) continue;

                const h = heuristics.estimate(self.heuristic, neighbor, end_grid);
                const tentative_g: f32 = current.g + h;

                if (visited.get(neighbor)) |existing_g| {
                    if (tentative_g >= existing_g) continue;
                }

                try visited.put(neighbor, tentative_g);
                try came_from.put(neighbor, current.pos);

                try open_set.add(.{
                    .pos = neighbor,
                    .g = tentative_g,
                    .h = h,
                });
            }
        }

        return null;
    }

    fn reconstructPath(
        self: *Pathfinder,
        allocator: mem.Allocator,
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
        var path = try allocator.alloc(Vec2, len);

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

const std = @import("std");
const mem = std.mem;
const engine = @import("engine");
const xmath = engine.math;
const heuristics = @import("path_finding_heuristics.zig");

const Vec2 = xmath.Vec2;
const GridPos = heuristics.GridPos;
const Heuristic = heuristics.Heuristic;
