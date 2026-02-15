pub const Screen = struct {
    width: u32,
    height: u32,
};

pub const Player = struct {
    entity: ecs.Entity,
};

pub const CameraState = struct {
    camera: rl.Camera2D,
};

pub const DebugState = struct {
    enabled: bool,
    values: std.StringHashMap([]const u8),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .enabled = false,
            .values = std.StringHashMap([]const u8).init(gpa),
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
};

pub const RenderTargets = struct {
    render_textures: std.StringHashMap(rl.RenderTexture),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .render_textures = std.StringHashMap(rl.RenderTexture).init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.render_textures.iterator();
        while (it.next()) |entry| {
            rl.UnloadRenderTexture(entry.value_ptr.*);
            self.gpa.free(entry.key_ptr.*);
        }
        self.render_textures.deinit();
    }

    pub fn loadRenderTexture(self: *Self, key: []const u8, width: c_int, height: c_int) !*rl.RenderTexture {
        const texture = rl.LoadRenderTexture(width, height);
        if (self.render_textures.getPtr(key)) |ptr| {
            rl.UnloadRenderTexture(ptr.*);
            ptr.* = texture;
            return ptr;
        }
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.render_textures.put(key_copy, texture);
        return self.render_textures.getPtr(key_copy).?;
    }

    pub fn unloadRenderTexture(self: *Self, key: []const u8) bool {
        const entry = self.render_textures.fetchRemove(key) orelse return false;
        rl.UnloadRenderTexture(entry.value);
        self.gpa.free(entry.key);
        return true;
    }
};

pub const Renderables = struct {
    list: renderables.RenderableList,
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .list = try renderables.RenderableList.initCapacity(gpa, 8),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.gpa);
    }
};

pub const RoomManager = struct {
    current: ?comps.Room,
    items: std.StringHashMap(void),
    bounds: std.AutoHashMap(u32, RoomBounds),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .current = null,
            .items = std.StringHashMap(void).init(gpa),
            .bounds = std.AutoHashMap(u32, RoomBounds).init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.items.keyIterator();
        while (it.next()) |key|
            self.gpa.free(key.*);
        self.items.deinit();
        self.bounds.deinit();
    }

    pub fn own(self: *Self, name: []const u8) ![]const u8 {
        if (self.items.getKey(name)) |exists| return exists;
        const name_copy = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(name_copy);
        try self.items.put(name_copy, {});
        return name_copy;
    }

    pub fn setBounds(self: *Self, room: comps.Room, bounds: RoomBounds) !void {
        try self.bounds.put(room.id, bounds);
    }

    pub fn getBounds(self: *Self, room: comps.Room) ?RoomBounds {
        return self.bounds.get(room.id);
    }
};

pub const RoomBounds = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const rl = engine.rl;
const ecs = engine.ecs;

const comps = @import("components.zig");
const renderables = @import("plugins/render/renderables.zig");
