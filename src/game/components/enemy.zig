pub const Enemy = struct {
    id: u8,
    speed: f32,
};

pub const EnemyView = struct {
    pub const Of = Enemy;
    id: *u8,
    speed: *f32,
};
