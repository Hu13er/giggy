pub fn serverInitSystem(app: *engine.core.App) !void {
    var host_mgr = app.getResource(plugins.net.resources.HostManager).?;
    try host_mgr.bind(.{
        .address = blk: {
            var addr: engine.net.resources.Address = .{};
            addr.setHostAny();
            addr.setPort(6969);
            break :blk addr;
        },
        .max_peers = 8,
    });
    std.debug.print("[!] engine.net.enet host binded\n", .{});
}

pub fn serverLoopSystem(app: *engine.core.App) !void {
    const host_mgr = app.getResource(plugins.net.resources.HostManager).?;

    var buffer: [4096]u8 = undefined;
    var pw = engine.net.wire.ProtocolWriter.init(app.gpa);
    defer pw.deinit();

    var peer_it = host_mgr.peers.keyIterator();
    while (peer_it.next()) |p| {
        var it = app.world.query(&[_]type{engine.net.Sync});
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

        const pkt = engine.net.enet.enet_packet_create(
            @ptrCast(data.ptr),
            data.len,
            engine.net.enet.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
        );
        const err = engine.net.enet.enet_peer_send(p.*, 0, pkt);
        if (err < 0)
            return engine.net.ENetError.ENetPeerSend;
    }

    while (try host_mgr.poll(5)) |event| {
        switch (event.type) {
            engine.net.enet.ENET_EVENT_TYPE_RECEIVE => {
                defer engine.net.enet.enet_packet_destroy(event.packet);
                // std.debug.print("[d][game][plugins][net][serverLoopSystem] Received packet: {d}\n", .{event.packet.*.dataLength});

                // TODO: handle packet
                // TODO: We don't know which client we're receiving data from. This must be handled via host manager.

                // TODO: Process client's incoming inputs
                var values: plugins.input.resources.Values = undefined;
                const data = blk: {
                    var v: []u8 = undefined;
                    v.ptr = @ptrCast(event.packet.*.data);
                    v.len = @intCast(event.packet.*.dataLength);
                    break :blk v;
                };
                var reader = std.io.Reader.fixed(data);

                try plugins.net.wire.readInput(&reader, &values);
                // std.debug.print("[d][game][plugins][net][serverLoopSystem] Received input values: {any}\n", .{values});
            },
            else => {},
        }
    }
}

pub fn serverTestInitSystem(app: *engine.core.App) !void {
    _ = try app.world.spawn(.{
        components.world.TestComponent{ .x = 0 },
        engine.net.Sync{},
    });
}

pub fn serverTestSystem(app: *engine.core.App) !void {
    var it = app.world.query(&[_]type{components.world.TestComponent});
    while (it.next()) |_| {
        const x = it.getAuto(components.world.TestComponent).x;
        x.* += 1;
    }
}

pub fn clientInitSystem(app: *engine.core.App) !void {
    var host_mgr = app.getResource(plugins.net.resources.HostManager).?;
    try host_mgr.bind(.{
        .address = null,
        .max_peers = 1,
    });
    try host_mgr.connect(blk: {
        var addr: engine.net.resources.Address = .{};
        try addr.setHost("127.0.0.1");
        addr.setPort(6969);
        break :blk addr;
    });
    std.debug.print("[!] engine.net.enet connected", .{});
}

pub fn clientLoopSystem(app: *engine.core.App) !void {
    const host_mgr = app.getResource(plugins.net.resources.HostManager).?;
    const comp_reg = app.getResource(engine.ecs.ComponentRegistry).?;

    if (host_mgr.firstPeer()) |peer| blk: { // first peer *should* be the server
        // Send input to server
        const input_res = app.getResource(plugins.input.resources.PlayerInput) orelse break :blk;

        var buffer: [256]u8 = undefined;
        var writer = std.io.Writer.fixed(buffer[0..]);
        try plugins.net.wire.writeInput(&writer, &input_res.current);

        const data = writer.buffered();
        const pkt = engine.net.enet.enet_packet_create(
            @ptrCast(data.ptr),
            data.len,
            engine.net.enet.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
        );
        const err = engine.net.enet.enet_peer_send(@ptrCast(peer), 0, pkt);
        if (err < 0)
            return engine.net.ENetError.ENetPeerSend;
    }

    while (try host_mgr.poll(5)) |event| {
        switch (event.type) {
            engine.net.enet.ENET_EVENT_TYPE_RECEIVE => {
                defer engine.net.enet.enet_packet_destroy(event.packet);

                const buffer = blk: {
                    const pkt = event.packet.*;
                    break :blk pkt.data[0..pkt.dataLength];
                };
                var r = io.Reader.fixed(buffer);
                var pr = engine.net.wire.ProtocolReader.init(comp_reg);
                defer pr.deinit();

                try pr.store(&app.world, &r);
            },
            else => {},
        }
    }
}

pub fn clientTestSystem(app: *engine.core.App) !void {
    const debug = app.getResource(game.plugins.debug.resources.DebugState).?;
    var it = app.world.query(&[_]type{components.world.TestComponent});
    while (it.next()) |_| {
        const x = it.getAuto(components.world.TestComponent).x;
        try debug.setFmt("test_value", "{d}", .{x.*});
    }
}

const std = @import("std");
const io = std.io;

const engine = @import("engine");
// const core = engine.core;
// const net = engine.net;
// const enet = net.enet;
// const xmath = engine.math;
// const rl = engine.raylib;

const game = @import("game");
const components = game.components;
const plugins = game.plugins;
