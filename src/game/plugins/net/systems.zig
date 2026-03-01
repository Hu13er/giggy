pub fn serverLoopSystem(app: *core.App) !void {
    const host_mgr = app.getResource(net.resources.HostManager).?;
    while (host_mgr.poll(5)) |event| {
        _ = event;
    }
}

pub fn clientLoopSystem(app: *core.App) !void {
    const host_mgr = app.getResource(net.resources.HostManager).?;

    while (host_mgr.poll(5)) |event| {
        switch (event) {
            else => {},
        }
    }

    // const peer = host_mgr.firstPeer() orelse return;
    // const input_resc = app.getResource(plugins.input.resources.PlayerInput).?;

}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const net = engine.net;
const enet = net.enet;
const xmath = engine.math;
const rl = engine.raylib;

const game = @import("game");
const components = game.components;
const plugins = game.plugins;

const resources = plugins.net.resources;
