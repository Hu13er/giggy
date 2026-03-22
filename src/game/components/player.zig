pub const Player = struct {
    id: u8,
    just_spawned: bool,
    // Which SpawnPoint.id to use on the next spawn. 0 means "any/default".
    spawn_id: u8 = 0,
};

pub const PlayerView = struct {
    pub const Of = Player;
    id: *u8,
    just_spawned: *bool,
    spawn_id: *u8,
};

pub const ClientPlayer = struct {
    id: u8,
};

pub const ClientPlayerView = struct {
    pub const Of = ClientPlayer;
    id: *u8,
};
