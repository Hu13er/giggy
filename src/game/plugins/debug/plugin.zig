pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.DebugState, resources.DebugState.init(app.gpa));
        try app.addSystem(.update, systems.updateDebugModeSystem, .{});
        try app.addSystem(.update, systems.updateDebugValuesSystem, .{});
        try app.addSystem(.render, systems.renderDebugSystem, .{
            .provides = &.{render.LabelRenderPass},
            .after_ids_optional = &.{render.RenderablesSystemId},
        });
        try app.addSystem(.render, systems.renderDebugOverlaySystem, .{
            .id = "debug.overlay",
            .provides = &.{render.LabelRenderOverlay},
            .after_ids_optional = &.{"fade.overlay"},
            .after_all_labels = &.{render.LabelRenderEndMode2D},
        });
    }
};
const core = engine.core;

const engine = @import("engine");
const game = @import("game");
const render = game.plugins.render;
const resources = @import("resources.zig");
const systems = @import("systems.zig");
