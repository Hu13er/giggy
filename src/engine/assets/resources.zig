pub const AssetManager = struct {
    textures: std.StringHashMap(rl.Texture),
    sprites: std.StringHashMap([]rl.Texture),
    models: std.StringHashMap(Model),
    shaders: std.StringHashMap(rl.Shader),
    configs: std.StringHashMap(Config),

    gpa: mem.Allocator,
    io: std.Io,

    const Self = @This();
    const Error = error{InvalidAssetBundle};
    const Config = json.Parsed(json.Value);

    pub fn init(io: std.Io, gpa: mem.Allocator) !Self {
        return Self{
            .textures = std.StringHashMap(rl.Texture2D).init(gpa),
            .sprites = std.StringHashMap([]rl.Texture).init(gpa),
            .models = std.StringHashMap(Model).init(gpa),
            .shaders = std.StringHashMap(rl.Shader).init(gpa),
            .configs = std.StringHashMap(Config).init(gpa),
            .gpa = gpa,
            .io = io,
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
            var it = self.sprites.iterator();
            while (it.next()) |entry| {
                for (entry.value_ptr.*) |t| rl.UnloadTexture(t);
                self.gpa.free(entry.key_ptr.*);
            }
            self.sprites.deinit();
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
        {
            var it = self.configs.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
                self.gpa.free(entry.key_ptr.*);
            }
            self.configs.deinit();
        }
    }

    pub fn loadBundle(self: *Self, bundle_filename: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(self.io, bundle_filename, .{});
        defer file.close(self.io);

        var file_reader = file.reader(self.io, &.{});
        const contents = try file_reader.interface.allocRemaining(
            self.gpa,
            .unlimited,
        );
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

        if (root.get("sprites")) |value| {
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
                _ = try self.loadSprites(entry.key_ptr.*, zpath);
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

        if (root.get("configs")) |value| {
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
                _ = try self.loadConfig(entry.key_ptr.*, path);
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

    pub fn loadSprites(self: *Self, key: []const u8, dirname: [:0]const u8) ![]rl.Texture2D {
        var dir = try std.Io.Dir.cwd().openDir(self.io, dirname, .{ .iterate = true });
        defer dir.close(self.io);

        var names: std.ArrayList([]u8) = .empty;
        defer {
            for (names.items) |n| self.gpa.free(n);
            names.deinit(self.gpa);
        }

        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".png")) continue;

            const name_copy = try self.gpa.dupe(u8, entry.name);
            errdefer self.gpa.free(name_copy);
            try names.append(self.gpa, name_copy);
        }

        std.mem.sort([]u8, names.items, {}, struct {
            fn lessThan(_: void, a: []u8, b: []u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        var loaded: std.ArrayList(rl.Texture2D) = .empty;
        errdefer {
            for (loaded.items) |t| rl.UnloadTexture(t);
            loaded.deinit(self.gpa);
        }

        for (names.items) |name| {
            const full_path = try std.fs.path.joinZ(self.gpa, &.{ dirname, name });
            defer self.gpa.free(full_path);

            const texture = rl.LoadTexture(@ptrCast(full_path));
            try loaded.append(self.gpa, texture);
        }

        const owned = try loaded.toOwnedSlice(self.gpa);

        if (self.sprites.getPtr(key)) |ptr| {
            for (ptr.*) |t| rl.UnloadTexture(t);
            self.gpa.free(ptr.*);
            ptr.* = owned;
            return owned;
        }
        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.sprites.put(key_copy, owned);
        return owned;
    }

    pub fn unloadSprites(self: *Self, key: []const u8) bool {
        const entry = self.sprites.fetchRemove(key) orelse return false;
        for (entry.value) |t| rl.UnloadTexture(t);
        self.gpa.free(entry.value);
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

    pub fn loadConfig(self: *Self, key: []const u8, filename: []const u8) !*json.Value {

        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(self.io, filename, .{});
        defer file.close(self.io);

        var file_reader = file.reader(self.io, &.{});
        const contents = try file_reader.interface.allocRemaining(
            self.gpa,
            .unlimited,
        );

        var parsed = try json.parseFromSlice(
            json.Value,
            self.gpa,
            contents,
            .{ .allocate = .alloc_always },
        );
        errdefer parsed.deinit();

        if (self.configs.getPtr(key)) |ptr| {
            ptr.deinit();
            ptr.* = parsed;
            return &ptr.value;
        }

        const key_copy = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(key_copy);
        try self.configs.put(key_copy, parsed);
        return &self.configs.getPtr(key_copy).?.value;
    }

    pub fn unloadConfig(self: *Self, key: []const u8) bool {
        const entry = self.configs.fetchRemove(key) orelse return false;
        entry.value.deinit();
        self.gpa.free(entry.key);
        return true;
    }

    pub fn getConfig(self: *Self, key: []const u8) ?*const json.Value {
        const entry = self.configs.getPtr(key) orelse return null;
        return &entry.value;
    }

    pub fn configValuePath(self: *Self, key: []const u8, path: []const []const u8) ?json.Value {
        var value = self.getConfig(key) orelse return null;
        for (path) |segment| {
            const obj = valueObject(value.*) orelse return null;
            const next = obj.get(segment) orelse return null;
            value = &next;
        }
        return value.*;
    }
    fn valueObject(value: json.Value) ?json.ObjectMap {
        return switch (value) {
            .object => |o| o,
            else => null,
        };
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
const engine = @import("engine");
const rl = engine.raylib;
