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

pub const HurtBox = struct {
    radius: f32,
    mask: u64,
};

pub const HurtBoxView = struct {
    pub const Of = HurtBox;
    radius: *f32,
    mask: *u64,
};
