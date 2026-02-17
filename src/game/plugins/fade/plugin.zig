pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.ScreenFade, .{});
        try app.addSystem(.fixed_update, systems.fadeSystem, .{
            .id = "fade.system",
            .provides = &.{"teleport"},
            .after_ids_optional = &.{"door.system"},
            .after_all_labels = &.{"physics"},
        });
        try app.addSystem(.render, systems.fadeOverlaySystem, .{
            .id = "fade.overlay",
            .provides = &.{render.LabelRenderOverlay},
            .after_all_labels = &.{render.LabelRenderEndMode2D},
        });
    }
};
const engine = @import("engine");
const core = engine.core;

const game = @import("game");
const render = game.plugins.render;
const resources = @import("resources.zig");
const systems = @import("systems.zig");
