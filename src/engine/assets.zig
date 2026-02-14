pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        var assets = try AssetManager.init(app.gpa);
        errdefer assets.deinit();
        _ = try app.insertResource(AssetManager, assets);
    }
};

pub const AssetManager = struct {
    textures: std.StringHashMap(rl.Texture),
    models: std.StringHashMap(Model),
    shaders: std.StringHashMap(rl.Shader),
    gpa: mem.Allocator,

    const Self = @This();
    const Error = error{InvalidAssetBundle};

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

    pub fn loadBundle(self: *Self, bundle_filename: []const u8) !void {
        var file = try fs.cwd().openFile(bundle_filename, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(self.gpa, math.maxInt(usize));
        defer self.gpa.free(contents);

        var parsed = try json.parseFromSlice(json.Value, self.gpa, contents, .{ .allocate = .alloc_always });
        defer parsed.deinit();

        const root = switch (parsed.value) {
            .object => |obj| obj,
            else => return Error.InvalidAssetBundle,
        };

        if (root.get("textures")) |value| {
            const obj = switch (value) {
                .object => |o| o,
                else => return Error.InvalidAssetBundle,
            };
            var it = obj.iterator();
            while (it.next()) |entry| {
                const path = switch (entry.value_ptr.*) {
                    .string => |s| s,
                    else => return Error.InvalidAssetBundle,
                };
                const zpath = try std.fmt.allocPrintSentinel(self.gpa, "{s}", .{path}, 0);
                defer self.gpa.free(zpath);
                _ = try self.loadTexture(entry.key_ptr.*, zpath);
            }
        }

        if (root.get("models")) |value| {
            const obj = switch (value) {
                .object => |o| o,
                else => return Error.InvalidAssetBundle,
            };
            var it = obj.iterator();
            while (it.next()) |entry| {
                const path = switch (entry.value_ptr.*) {
                    .string => |s| s,
                    else => return Error.InvalidAssetBundle,
                };
                const zpath = try std.fmt.allocPrintSentinel(self.gpa, "{s}", .{path}, 0);
                defer self.gpa.free(zpath);
                _ = try self.loadModel(entry.key_ptr.*, zpath);
            }
        }

        if (root.get("shaders")) |value| {
            const obj = switch (value) {
                .object => |o| o,
                else => return Error.InvalidAssetBundle,
            };
            var it = obj.iterator();
            while (it.next()) |entry| {
                const shader_obj = switch (entry.value_ptr.*) {
                    .object => |o| o,
                    else => return Error.InvalidAssetBundle,
                };
                const vs_value = shader_obj.get("vs") orelse return Error.InvalidAssetBundle;
                const fs_value = shader_obj.get("fs") orelse return Error.InvalidAssetBundle;
                const vs_path = switch (vs_value) {
                    .string => |s| s,
                    else => return Error.InvalidAssetBundle,
                };
                const fs_path = switch (fs_value) {
                    .string => |s| s,
                    else => return Error.InvalidAssetBundle,
                };
                const vs_z = try std.fmt.allocPrintSentinel(self.gpa, "{s}", .{vs_path}, 0);
                defer self.gpa.free(vs_z);
                const fs_z = try std.fmt.allocPrintSentinel(self.gpa, "{s}", .{fs_path}, 0);
                defer self.gpa.free(fs_z);
                _ = try self.loadShader(entry.key_ptr.*, vs_z, fs_z);
            }
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

    pub fn unload(self: *const Model) void {
        rl.UnloadModelAnimations(
            @ptrCast(self.animations.ptr),
            @intCast(self.animations.len),
        );
        rl.UnloadModel(self.model);
    }
};

const std = @import("std");
const mem = std.mem;
const json = std.json;
const fs = std.fs;
const math = std.math;
const rl = @import("rl.zig").rl;
const core = @import("core.zig");
