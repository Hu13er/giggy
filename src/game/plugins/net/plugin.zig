pub const Plugin = struct {
    host_type: HostType,

    pub const HostType = enum {
        client,
        server,
    };

    pub fn build(self: @This(), app: *core.App) !void {
        switch (self.host_type) {
            .client => {
                app.addSystem(.fixed_update, systems.clientLoopSystem, .{
                    .provides = &.{"network.tick"},
                    .after_all_labels = &.{"input"},
                });
            },
            .server => {
                app.addSystem(.fixed_update, systems.serverLoopSystem, .{
                    .provides = &.{"network.tick"},
                });
            },
        }
    }
};

const std = @import("std");

const engine = @import("engine");
const core = engine.core;

const game = @import("game");
const resources = game.plugins.net.resources;
const systems = game.plugins.net.systems;
