pub const EnemyState = enum {
    chase,
    charge,
    dead,
};

pub const Enemy = struct {
    id: u8,
    speed: f32,
    state: EnemyState,
    release_tick: u32, // zero means null
};

pub const EnemyView = struct {
    pub const Of = Enemy;
    id: *u8,
    speed: *f32,
    state: *EnemyState,
    release_tick: *u32,
};

pub const Shockwave = struct {
    size: f32 = 0,
    size_init: f32,
    size_limit: f32,
    damage: i16,
    ttl: f32,
    accum: f32 = 0,
};

pub const ShockwaveView = struct {
    pub const Of = Shockwave;
    size: *f32,
    size_init: *f32,
    size_limit: *f32,
    damage: *i16,
    ttl: *f32,
    accum: *f32,
};

pub const ShockwaveHitbox = struct {
    width: f32 = 0,
    height: f32 = 0,
    mask: u64,
    accum: u32 = 0,
};

pub const ShockwaveHitboxView = struct {
    pub const Of = ShockwaveHitbox;
    width: *f32,
    height: *f32,
    mask: *u64,
    accum: *u32,
};
