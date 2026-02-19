pub const DebugState = struct {
    enabled: bool,
    values: std.StringHashMap([]const u8),
    points: std.ArrayList(DebugPoint),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .enabled = false,
            .values = std.StringHashMap([]const u8).init(gpa),
            .points = try std.ArrayListUnmanaged(DebugPoint).initCapacity(gpa, 1),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.values.deinit();
        self.points.deinit(self.gpa);
    }

    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        if (self.values.getPtr(key)) |ptr| {
            const value_copy = try self.gpa.dupe(u8, value);
            self.gpa.free(ptr.*);
            ptr.* = value_copy;
            return;
        }

        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        const value_copy = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(value_copy);
        try self.values.put(key_copy, value_copy);
    }

    pub fn setFmt(self: *Self, key: []const u8, comptime fmt: []const u8, args: anytype) !void {
        const value = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(value);
        try self.set(key, value);
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        const entry = self.values.fetchRemove(key) orelse return false;
        self.gpa.free(entry.key);
        self.gpa.free(entry.value);
        return true;
    }

    pub fn clear(self: *Self) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.values.clearRetainingCapacity();
    }

    pub fn addPoint(self: *Self, point: DebugPoint) !void {
        try self.points.append(self.gpa, point);
    }

    pub fn clearPoints(self: *Self) void {
        self.points.clearRetainingCapacity();
    }
};

pub const DebugPoint = struct {
    x: f32,
    y: f32,
    radius: f32 = 4.0,
    color: rl.Color = rl.RED,
};

const std = @import("std");
const mem = std.mem;
const engine = @import("engine");
const rl = engine.raylib;
