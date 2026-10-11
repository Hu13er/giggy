pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = try app.insertResource(resources.BarResource, .init());
        try app.addSystem(.render, systems.renderHealthSystem, .{
            .provides = &.{LabelRenderHUD, game.plugins.render.LabelRenderOverlay},
            .after_all_labels = &.{game.plugins.render.LabelRenderEndMode2D},
        });
    }
};

pub const LabelRenderHUD = "render.hud";

const std = @import("std");

const engine = @import("engine");
const core = engine.core;

const game = @import("game");
const components = game.components;
const systems = game.plugins.hud.systems;
const resources = game.plugins.hud.resources;
