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
};

pub const Level = struct {
    file_path: []const u8,
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

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const rl = engine.rl;
const ecs = engine.ecs;

const renderables = @import("plugins/render/renderables.zig");
