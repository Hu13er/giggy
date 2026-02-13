pub const AssetManager = struct {
    textures: std.StringHashMap(rl.Texture2D),
    models: std.StringHashMap(Model),
    shaders: std.StringHashMap(rl.Shader),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return Self{
            .textures = std.StringHashMap(rl.Texture2D).init(gpa),
            .models = std.StringHashMap(Model).init(gpa),
            .shaders = std.StringHashMap(rl.Shader).init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        {
            var it = self.textures.iterator();
            while (it.next()) |entry| {
                rl.UnloadTexture(entry.value_ptr.*);
                self.gpa.free(entry.key_ptr.*);
            }
            self.textures.deinit();
        }
        {
            var it = self.models.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.unload();
                self.gpa.free(entry.key_ptr.*);
            }
            self.models.deinit();
        }
        {
            var it = self.shaders.iterator();
            while (it.next()) |entry| {
                rl.UnloadShader(entry.value_ptr.*);
                self.gpa.free(entry.key_ptr.*);
            }
            self.shaders.deinit();
        }
    }

    pub fn loadTexture(self: *Self, key: []const u8, filename: [:0]const u8) !*rl.Texture2D {
        const texture = rl.LoadTexture(@ptrCast(filename));
        if (self.textures.getPtr(key)) |ptr| {
            rl.UnloadTexture(ptr.*);
            ptr.* = texture;
            return ptr;
        }
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.textures.put(key_copy, texture);
        return self.textures.getPtr(key_copy).?;
    }

    pub fn unloadTexture(self: *Self, key: []const u8) bool {
        const entry = self.textures.fetchRemove(key) orelse return false;
        rl.UnloadTexture(entry.value);
        self.gpa.free(entry.key);
        return true;
    }

    pub fn loadModel(self: *Self, key: []const u8, filename: [:0]const u8) !*Model {
        const model = Model.load(filename);
        if (self.models.getPtr(key)) |m| {
            m.unload();
            m.* = model;
            return m;
        }
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.models.put(key_copy, model);
        return self.models.getPtr(key_copy).?;
    }

    pub fn unloadModel(self: *Self, key: []const u8) bool {
        const entry = self.models.fetchRemove(key) orelse return false;
        entry.value.unload();
        self.gpa.free(entry.key);
        return true;
    }

    pub fn loadShader(self: *Self, key: []const u8, vs_filename: [:0]const u8, fs_filename: [:0]const u8) !*rl.Shader {
        const shader = rl.LoadShader(
            @ptrCast(vs_filename),
            @ptrCast(fs_filename),
        );
        if (self.shaders.getPtr(key)) |ptr| {
            rl.UnloadShader(ptr.*);
            ptr.* = shader;
            return ptr;
        }
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.shaders.put(key_copy, shader);
        return self.shaders.getPtr(key_copy).?;
    }

    pub fn unloadShader(self: *Self, key: []const u8) bool {
        const entry = self.shaders.fetchRemove(key) orelse return false;
        rl.UnloadShader(entry.value);
        self.gpa.free(entry.key);
        return true;
    }
};

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
const rl = @import("engine").rl;
