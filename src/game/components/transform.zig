pub const RawPosition = struct {
    x: f32,
    y: f32,
};

pub const RawPositionView = struct {
    pub const Of = RawPosition;
    x: *f32,
    y: *f32,
};

pub const RawRotation = struct {
    target_teta: f32,
};

pub const RawRotationView = struct {
    pub const Of = RawRotation;
    target_teta: *f32,
};

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
