pub const ENetInitializer = struct {
    ret_code: ?c_int = null,

    const Self = @This();

    pub fn init() !Self {
        const ret_code = enet.enet_initialize();
        if (ret_code < 0) {
            std.debug.print("[!] ENet init Error: {d}\n", .{ret_code});
            return ENetError.InitError;
        }
        std.debug.print("[!] ENet init successfully\n", .{});
        return .{ .ret_code = ret_code };
    }

    pub fn deinit(self: *Self) void {
        if (self.ret_code == null) return;
        self.ret_code = null;
        enet.enet_deinitialize();
        std.debug.print("[!] ENet deinit successfully\n", .{});
    }
};

pub const HostManager = struct {
    host: ?*enet.ENetHost,
    peers: PeersSet,

    const Self = @This();
    const PeersSet = std.AutoHashMap(*enet.ENetPeer, void);

    pub const Config = struct {
        address: Address,
        max_peers: usize,
    };

    pub fn init(gpa: mem.Allocator) !Self {
        return Self{
            .host = null,
            .peers = PeersSet.init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.peers.deinit();
        enet.enet_host_destroy(@ptrCast(self.host));
    }

    pub fn bind(self: *Self, cfg: Config) !void {
        const server = enet.enet_host_create(
            @ptrCast(&cfg.address.inner),
            cfg.max_peers,
            2, // channels
            0, // downstream bandwith (0 = unlimited)
            0, // upstream bandwith (0 = unlimited)
        );
        if (server == null) return ENetError.CreateHostError;
        self.host = @ptrCast(server);
    }

    pub fn connect(self: *Self, addr: Address) !void {
        const peer = enet.enet_host_connect(
            @ptrCast(self.host),
            @ptrCast(&addr.inner),
            2,
            0,
        );
        if (peer == null) return ENetError.CreateHostError;
    }

    pub fn poll(self: *Self, timeout: u32) !?enet.ENetEvent {
        var event: enet.ENetEvent = undefined;
        const ret = enet.enet_host_service(
            @ptrCast(self.host.?),
            @ptrCast(&event),
            timeout,
        );
        if (ret <= 0) return null;
        switch (event.type) {
            enet.ENET_EVENT_TYPE_CONNECT => {
                try self.peers.put(event.peer, {});
            },
            enet.ENET_EVENT_TYPE_DISCONNECT => {
                _ = self.peers.remove(event.peer);
            },
            else => {},
        }
        return event;
    }

    pub fn firstPeer(self: *const Self) ?*enet.ENetPeer {
        var iter = self.peers.keyIterator();
        return iter.next();
    }
};

pub const Address = struct {
    inner: enet.ENetAddress = .{},

    const Self = @This();

    pub fn setHostAny(self: *Self) void {
        self.inner.host = .{};
    }

    pub fn setHost(self: *Self, hostname: []const u8) !void {
        const err = enet.enet_address_set_host(
            self.ptr(),
            @ptrCast(hostname),
        );
        if (err != 0) return ENetError.InvalidAddress;
    }

    pub fn setPort(self: *Self, port: u16) void {
        self.inner.port = port;
    }
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const enet = engine.net.enet;
const ENetError = engine.net.ENetError;
