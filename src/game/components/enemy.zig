pub const EnemyState = enum {
    chase,
    charge,
    dead,
};

pub const Enemy = struct {
    id: u8,
    speed: f32,
    state: EnemyState,
};

pub const EnemyView = struct {
    pub const Of = Enemy;
    id: *u8,
    speed: *f32,
    state: *EnemyState,
};
