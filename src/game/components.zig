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
};

pub const ColliderCircleView = struct {
    pub const Of = ColliderCircle;
    radius: *f32,
};

pub const ColliderLine = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
};

pub const ColliderLineView = struct {
    pub const Of = ColliderLine;
    x0: *f32,
    y0: *f32,
    x1: *f32,
    y1: *f32,
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

pub const MoveAnimation = struct {
    idle: usize,
    run: usize,
    speed: f32,
};

pub const MoveAnimationView = struct {
    pub const Of = MoveAnimation;
    idle: *usize,
    run: *usize,
    speed: *f32,
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
};

pub const TextureView = struct {
    pub const Of = Texture;
    name: *[]const u8,
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
