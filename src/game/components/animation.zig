pub const Animation = struct {
    index: usize,
    speed: f32,
    frame: usize,
    accum: f32,
    count: u8 = 0,
    priority: i16,
};

pub const AnimationView = struct {
    pub const Of = Animation;
    index: *usize,
    speed: *f32,
    frame: *usize,
    accum: *f32,
    count: *u8,
    priority: *i16,
};

pub const LocomotionAnimSet = struct {
    // Animation index for idle (model.animations[...]).
    idle: usize,
    // Animation index for run (model.animations[...]).
    run: usize,
    // Base playback speed in frames per second.
    base_speed: f32,
    // Movement speed that maps to base_speed (scales playback).
    run_speed_ref: f32,
    // Velocity magnitude threshold to enter "moving".
    move_start: f32,
    // Velocity magnitude threshold to exit "moving".
    move_stop: f32,
    // Min playback multiplier when moving.
    speed_scale_min: f32,
    // Max playback multiplier when moving.
    speed_scale_max: f32,
};

pub const LocomotionAnimSetView = struct {
    pub const Of = LocomotionAnimSet;
    idle: *usize,
    run: *usize,
    base_speed: *f32,
    run_speed_ref: *f32,
    move_start: *f32,
    move_stop: *f32,
    speed_scale_min: *f32,
    speed_scale_max: *f32,
};

pub const SkullAnimSet = struct {
    attack: usize,
    attack_count: u8,
    dead: usize,
    dead_speed: f32,
};

pub const SkullAnimSetView = struct {
    pub const Of = SkullAnimSet;
    attack: *usize,
    attack_count: *u8,
    dead: *usize,
    dead_speed: *f32,
};

pub const GhostAnimSet = struct {
    idle: usize,
    idle_speed: f32,
    attack: usize,
};

pub const GhostAnimSetView = struct {
    pub const Of = GhostAnimSet;
    idle: *usize,
    idle_speed: *f32,
    attack: *usize,
};

pub const LocomotionAnimState = struct {
    moving: bool,
};

pub const LocomotionAnimStateView = struct {
    pub const Of = LocomotionAnimState;
    moving: *bool,
};
