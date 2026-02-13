pub const AssetsPlugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;
        try assets_mgr.loadBundle("resources/bundle.json");

        const greenman_model = assets_mgr.models.getPtr("greenman").?;
        const skinning_shader = assets_mgr.shaders.getPtr("skinning").?;
        greenman_model.model.materials[1].shader = skinning_shader.*;
    }
};

const engine = @import("engine");
const core = engine.core;
