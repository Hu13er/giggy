pub const RenderTargets = struct {
    // We use HashMaps instead of ArrayList so
    // we can notice dangling refs to died render targets
    render_textures: std.AutoHashMap(u32, rl.RenderTexture),
    next_id: u32,
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .render_textures = .init(gpa),
            .next_id = 0,
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.render_textures.iterator();
        while (it.next()) |entry| {
            rl.UnloadRenderTexture(entry.value_ptr.*);
        }
        self.render_textures.deinit();
    }

    pub fn load(self: *Self, width: c_int, height: c_int) !u32 {
        const texture = rl.LoadRenderTexture(width, height);
        const id = self.next_id;
        self.next_id += 1;
        errdefer self.next_id = id;
        try self.render_textures.put(id, texture);
        return id;
    }

    pub fn unload(self: *Self, key: u32) bool {
        const entry = self.render_textures.fetchRemove(key) orelse return false;
        rl.UnloadRenderTexture(entry.value);
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
const rl = engine.raylib;

const renderables = @import("renderables.zig");
