pub const Position = struct {
    x: f32,
    y: f32,
    prev_x: f32,
    prev_y: f32,
};

pub const PositionView = struct {
    pub const Of = Position;
    x: *f32,
    y: *f32,
    prev_x: *f32,
    prev_y: *f32,
};

pub const Velocity = struct {
    x: f32,
    y: f32,
};

pub const VelocityView = struct {
    pub const Of = Velocity;
    x: *f32,
    y: *f32,
};

pub const ColliderCircle = struct {
    radius: f32,
    mask: u64,
};

pub const ColliderCircleView = struct {
    pub const Of = ColliderCircle;
    radius: *f32,
    mask: *u64,
};

pub const ColliderLine = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    mask: u64,
};

pub const ColliderLineView = struct {
    pub const Of = ColliderLine;
    x0: *f32,
    y0: *f32,
    x1: *f32,
    y1: *f32,
    mask: *u64,
};

pub const Model3D = struct {
    name: []const u8,
    mesh: usize,
    material: usize,
    render_texture: usize,
};

pub const Model3DView = struct {
    pub const Of = Model3D;
    name: *[]const u8,
    mesh: *usize,
    material: *usize,
    render_texture: *usize,
};

pub const Animation = struct {
    index: usize,
    speed: f32,
    frame: usize,
    acc: f32,
};

pub const AnimationView = struct {
    pub const Of = Animation;
    index: *usize,
    speed: *f32,
    frame: *usize,
    acc: *f32,
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

pub const LocomotionAnimState = struct {
    moving: bool,
};

pub const LocomotionAnimStateView = struct {
    pub const Of = LocomotionAnimState;
    moving: *bool,
};

pub const Rotation = struct {
    teta: f32,
    prev_teta: f32,
    target_teta: f32,
    turn_speed_deg: f32,
};

pub const RotationView = struct {
    pub const Of = Rotation;
    teta: *f32,
    prev_teta: *f32,
    target_teta: *f32,
    turn_speed_deg: *f32,
};

pub const Texture = struct {
    name: []const u8,
    z_index: i16,
};

pub const TextureView = struct {
    pub const Of = Texture;
    name: *[]const u8,
    z_index: *i16,
};

pub const WidthHeight = struct {
    w: f32,
    h: f32,
};

pub const WidthHeightView = struct {
    pub const Of = WidthHeight;
    w: *f32,
    h: *f32,
};

pub const RenderInto = struct {
    into: []const u8,
};

pub const RenderIntoView = struct {
    pub const Of = RenderInto;
    into: *[]const u8,
};
