pub const AssetsPlugin = struct {
    bundle: []const u8 = "resources/bundle.json",

    pub fn build(self: @This(), app: *core.App) !void {
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;
        try assets_mgr.loadBundle(self.bundle);

        const greenman_model = assets_mgr.models.getPtr("greenman");
        const skinning_shader = assets_mgr.shaders.getPtr("skinning");
        if (greenman_model != null and skinning_shader != null) {
            greenman_model.?.model.materials[1].shader = skinning_shader.?.*;
        }
    }
};

const engine = @import("engine");
const core = engine.core;
