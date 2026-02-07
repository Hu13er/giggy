pub const screenWidth: u32 = 800;
pub const screenHeight: u32 = 600;

textures: std.StringHashMap(rl.Texture2D),
render_textures: std.StringHashMap(rl.RenderTexture),
models: std.StringHashMap(Model),
shaders: std.StringHashMap(rl.Shader),
jsons: std.StringHashMap(map_loader.ParsedLayer),
gpa: mem.Allocator,
debug: bool,

const Self = @This();

pub fn init(gpa: mem.Allocator) !Self {
    return Self{
        .textures = std.StringHashMap(rl.Texture2D).init(gpa),
        .render_textures = std.StringHashMap(rl.RenderTexture).init(gpa),
        .models = std.StringHashMap(Model).init(gpa),
        .shaders = std.StringHashMap(rl.Shader).init(gpa),
        .jsons = std.StringHashMap(map_loader.ParsedLayer).init(gpa),
        .gpa = gpa,
        .debug = false,
    };
}

pub fn deinit(self: *Self) void {
    {
        var it = self.textures.keyIterator();
        while (it.next()) |key|
            _ = self.unloadTexture(key.*);
    }
    {
        var it = self.models.keyIterator();
        while (it.next()) |key|
            _ = self.unloadModel(key.*);
    }
    {
        var it = self.shaders.keyIterator();
        while (it.next()) |key|
            _ = self.unloadShader(key.*);
    }
    {
        var it = self.jsons.keyIterator();
        while (it.next()) |key|
            _ = self.unloadJson(key.*);
    }
}

pub fn loadTexture(self: *Self, key: []const u8, filename: [:0]const u8) !*rl.Texture2D {
    const texture = rl.LoadTexture(@ptrCast(filename));
    try self.textures.put(key, texture);
    return self.textures.getPtr(key).?;
}

pub fn unloadTexture(self: *Self, key: []const u8) bool {
    const ptr = self.textures.getPtr(key) orelse return false;
    rl.UnloadTexture(ptr.*);
    return self.textures.remove(key);
}

pub fn loadRenderTexture(self: *Self, key: []const u8, width: c_int, height: c_int) !*rl.RenderTexture {
    const texture = rl.LoadRenderTexture(width, height);
    try self.render_textures.put(key, texture);
    return self.render_textures.getPtr(key).?;
}

pub fn unloadRenderTexture(self: *Self, key: []const u8) bool {
    const ptr = self.render_textures.getPtr(key) orelse return false;
    rl.UnloadRenderTexture(ptr.*);
    return self.render_textures.remove(key);
}

pub fn loadModel(self: *Self, key: []const u8, filename: [:0]const u8) !*Model {
    const model = Model.load(filename);
    try self.models.put(key, model);
    return self.models.getPtr(key).?;
}

pub fn unloadModel(self: *Self, key: []const u8) bool {
    const ptr = self.models.getPtr(key) orelse return false;
    ptr.unload();
    return self.models.remove(key);
}

pub fn loadShader(self: *Self, key: []const u8, vs_filename: [:0]const u8, fs_filename: [:0]const u8) !*rl.Shader {
    const shader = rl.LoadShader(
        @ptrCast(vs_filename),
        @ptrCast(fs_filename),
    );
    try self.shaders.put(key, shader);
    return self.shaders.getPtr(key).?;
}

pub fn unloadShader(self: *Self, key: []const u8) bool {
    const ptr = self.shaders.getPtr(key) orelse return false;
    rl.UnloadShader(ptr.*);
    return self.textures.remove(key);
}

pub fn loadJson(self: *Self, key: []const u8, filename: []const u8) !*map_loader.ParsedLayer {
    const json = try map_loader.loadLayer(self.gpa, filename);
    try self.jsons.put(key, json);
    return self.jsons.getPtr(key).?;
}

pub fn unloadJson(self: *Self, key: []const u8) bool {
    const ptr = self.jsons.getPtr(key) orelse return false;
    ptr.deinit();
    return self.jsons.remove(key);
}

pub const Model = struct {
    model: rl.Model,
    animations: []rl.ModelAnimation,

    pub fn load(filename: [:0]const u8) Model {
        const model = rl.LoadModel(@ptrCast(filename));
        var anim_count: c_int = undefined;
        const anim = rl.LoadModelAnimations(filename, &anim_count);
        return Model{
            .model = model,
            .animations = anim[0..@as(usize, @intCast(anim_count))],
        };
    }

    pub fn unload(self: *Model) void {
        rl.UnloadModelAnimations(
            @ptrCast(self.animations.ptr),
            @intCast(self.animations.len),
        );
        rl.UnloadModel(self.model);
    }
};

const std = @import("std");
const mem = std.mem;
const rl = @import("../rl.zig").rl;
const map_loader = @import("map_loader.zig");
