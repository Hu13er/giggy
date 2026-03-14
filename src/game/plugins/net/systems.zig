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
        if (data.len == 0) continue;

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
    var host_mgr = app.getResource(net.resources.HostManager).?;
    try host_mgr.connect(blk: {
        var addr: net.resources.Address = .{};
        addr.setHost("127.0.0.1");
        addr.setPort(6969);
        break :blk addr;
    });
    std.debug.print("[!] ENet connected", .{});
}

pub fn clientLoopSystem(app: *core.App) !void {
    const host_mgr = app.getResource(net.resources.HostManager).?;
    const comp_reg = app.getResource(engine.ecs.ComponentRegistry).?;

    // TODO
    // const peer = host_mgr.firstPeer() orelse return;
    // const input_resc = app.getResource(plugins.input.resources.PlayerInput).?;

    while (try host_mgr.poll(5)) |event| {
        switch (event.type) {
            enet.ENET_EVENT_TYPE_RECEIVE => {
                defer enet.enet_packet_destroy(event.packet);
                std.debug.print("[*] Got packet: {d}", .{event.packet.*.dataLength});

                const buffer = blk: {
                    const pkt = event.packet.*;
                    break :blk pkt.data[0..pkt.dataLength];
                };
                var r = io.Reader.fixed(buffer);
                var pr = net.wire.ProtocolReader.init(comp_reg);
                defer pr.deinit();

                try pr.store(app.world, &r);
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
