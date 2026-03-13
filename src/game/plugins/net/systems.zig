pub fn serverInitSystem(app: *core.App) !void {
    var host_mgr = app.getResource(net.resources.HostManager).?;
    try host_mgr.bind(.{
        .address = blk: {
            var addr: net.resources.Address = .{};
            addr.setHostAny();
            addr.setPort(6969);
            break :blk addr;
        },
        .max_peers = 8,
    });
    std.debug.print("[!] ENet host binded\n", .{});
}

pub fn serverLoopSystem(app: *core.App) !void {
    const host_mgr = app.getResource(net.resources.HostManager).?;

    var buffer: [4096]u8 = undefined;
    var pw = net.wire.ProtocolWriter.init(app.gpa);
    defer pw.deinit();

    var peer_it = host_mgr.peers.keyIterator();
    while (peer_it.next()) |p| {
        var it = app.world.query(&[_]type{net.Sync});
        while (it.next()) |_| {
            // filter only relevant entities here.
            // ...
            const entry = it.entry();
            try pw.push(entry.archetype, entry.row);
        }

        var w = io.Writer.fixed(buffer[0..]);
        try pw.flush(&w);
        const data = w.buffered();

        const pkt = enet.enet_packet_create(
            @ptrCast(data.ptr),
            data.len,
            enet.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
        );
        const err = enet.enet_peer_send(p.*, 0, pkt);
        if (err < 0) return net.ENetError.ENetPeerSend;
    }

    while (try host_mgr.poll(5)) |event| {
        switch (event.type) {
            enet.ENET_EVENT_TYPE_RECEIVE => {
                std.debug.print("[*] Got packet: {d}", .{event.packet.*.dataLength});
                enet.enet_packet_destroy(event.packet);
            },
            else => {},
        }
    }
}

pub fn clientInitSystem(app: *core.App) !void {
    // TODO
    //

    _ = app;
}

pub fn clientLoopSystem(app: *core.App) !void {
    // TODO
    //

    const host_mgr = app.getResource(net.resources.HostManager).?;

    // const peer = host_mgr.firstPeer() orelse return;
    // const input_resc = app.getResource(plugins.input.resources.PlayerInput).?;

    while (try host_mgr.poll(5)) |event| {
        switch (event.type) {
            enet.ENET_EVENT_TYPE_RECEIVE => {
                std.debug.print("[*] Got packet: {d}", .{event.packet.*.dataLength});
                enet.enet_packet_destroy(event.packet);
            },
            else => {},
        }
    }
}

const std = @import("std");
const io = std.io;

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
