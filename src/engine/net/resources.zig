pub const ENetInitializer = struct {
    ret_code: ?c_int,

    const Self = @This();

    pub fn init() !Self {
        const ret_code = enet.enet_initialize();
        if (ret_code < 0) return ENetError.InitError;
        return .{ .ret_code = ret_code };
    }

    pub fn deinit(self: *Self) void {
        if (self.ret_code == null) return;
        self.ret_code = null;
        enet.enet_deinitialize();
    }
};

pub const Server = struct {
    server: *enet.ENetHost,
    address: enet.ENetAddress,
    config: Config,

    const Self = @This();

    pub const Config = struct {
        port: u16,
        max_peers: usize,
    };

    pub fn init(config: Config) !Self {
        const self = Self{
            .server = undefined,
            .address = enet.ENetAddress{
                .host = enet.ENET_HOST_ANY,
                .port = config.port,
            },
            .config = config,
        };

        const server = enet.enet_host_create(
            @ptrCast(&self.address),
            self.config.max_peers,
            2, // channels
            0, // downstream bandwith (0 = unlimited)
            0, // upstream bandwith (0 = unlimited)
        );
        if (server == null) return ENetError.CreateHostError;
        self.server = @ptrCast(server);

        return self;
    }

    pub fn deinit(self: *Self) void {
        enet.enet_host_destroy(@ptrCast(self.server));
    }
};

pub const ENetError = error{
    InitError,
    CreateHostError,
};

const std = @import("std");

const engine = @import("engine");
const enet = engine.net.enet;
