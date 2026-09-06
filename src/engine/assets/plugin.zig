pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        var assets = try resources.AssetManager.init(app.io, app.gpa);
        errdefer assets.deinit();
        _ = try app.insertResource(resources.AssetManager, assets);
    }
};

const engine = @import("engine");
const core = engine.core;
const resources = @import("resources.zig");
