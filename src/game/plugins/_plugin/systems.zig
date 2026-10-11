pub fn sampleSystem(app: *core.App) !void {
    const res = app.getResource(resources.SampleResource).?;
    _ = res;
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;

const game = @import("game");
const components = game.components;
const resources = game.plugins._plugin.resources;
