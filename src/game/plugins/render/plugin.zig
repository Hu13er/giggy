pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        var render_targets = try resources.RenderTargets.init(app.gpa);
        errdefer render_targets.deinit();
        _ = try app.insertResource(resources.RenderTargets, render_targets);

        var renderables_state = try resources.Renderables.init(app.gpa);
        errdefer renderables_state.deinit();
        _ = try app.insertResource(resources.Renderables, renderables_state);

        try app.addSystem(.fixed_update, systems.updateLocomotionAnimationSystem, .{
            .provides = &.{ "animation", "animation.set" },
            .after_all_labels = &.{"physics"},
        });
        try app.addSystem(.update, systems.update3DModelAnimationsSystem, .{
            .provides = &.{ "animation", "animation.update" },
            .after_all_labels = &.{"animation.set"},
        });
        try app.addSystem(.render, systems.render3DModelsSystem, .{
            .provides = &.{systems.LabelRenderPrepass},
            .after_all_labels = &.{"animation.update"},
        });
        try app.addSystem(.render, systems.renderBeginSystem, .{
            .provides = &.{systems.LabelRenderBegin},
            .after_all_labels = &.{systems.LabelRenderPrepass},
        });
        try app.addSystem(.render, systems.collectRenderablesSystem, .{
            .id = systems.CollectRenderablesSystemId,
            .provides = &.{systems.LabelRenderPass},
            .after_all_labels = &.{systems.LabelRenderBegin},
        });
        try app.addSystem(.render, systems.renderRenderablesSystem, .{
            .id = systems.RenderRenderablesSystemId,
            .provides = &.{systems.LabelRenderPass},
            .after_ids = &.{systems.CollectRenderablesSystemId},
        });
        try app.addSystem(.render, systems.renderEndMode2DSystem, .{
            .provides = &.{systems.LabelRenderEndMode2D},
            .after_all_labels = &.{systems.LabelRenderPass},
        });
        try app.addSystem(.render, systems.renderEndSystem, .{
            .provides = &.{systems.LabelRenderEnd},
            .after_all_labels = &.{ systems.LabelRenderEndMode2D, systems.LabelRenderOverlay },
        });
        try app.addSystem(.render, systems.clearRenderablesSystem, .{
            .after_all_labels = &.{systems.LabelRenderEnd},
        });
    }
};

const engine = @import("engine");
const core = engine.core;

const resources = @import("resources.zig");
const systems = @import("systems.zig");
