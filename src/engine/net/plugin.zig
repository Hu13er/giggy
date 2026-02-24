pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) void {
        _ = self;
        _ = app;
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const resources = engine.net.resources;
const systems = engine.net.systems;
