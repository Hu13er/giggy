pub const Position = struct {
    pub const cid = 1;
    x: f32,
    y: f32,
};

pub const PositionView = struct {
    pub const Of = Position;
    x: *f32,
    y: *f32,
};

pub const Velocity = struct {
    pub const cid = 2;
    x: f32,
    y: f32,
};

pub const VelocityView = struct {
    pub const Of = Velocity;
    x: *f32,
    y: *f32,
};

pub const Circle = struct {
    pub const cid = 3;
    color: rl.Color,
    r: f32,
};

pub const CircleView = struct {
    pub const Of = Circle;
    color: *rl.Color,
    r: *f32,
};

pub const Model3D = struct {
    pub const cid = 4;
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
    pub const cid = 5;
    index: usize,
    frame: usize,
};

pub const AnimationView = struct {
    pub const Of = Animation;
    index: *usize,
    frame: *usize,
};

pub const MoveAnimation = struct {
    pub const cid = 6;
    idle: usize,
    run: usize,
};

pub const MoveAnimationView = struct {
    pub const Of = MoveAnimation;
    idle: *usize,
    run: *usize,
};

pub const Rotation = struct {
    pub const cid = 7;
    teta: f32,
};

pub const RotationView = struct {
    pub const Of = Rotation;
    teta: *f32,
};

pub const Texture = struct {
    pub const cid = 8;
    name: []const u8,
};

pub const TextureView = struct {
    pub const Of = Texture;
    name: *[]const u8,
};

pub const Line = struct {
    pub const cid = 9;
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
};

pub const LineView = struct {
    pub const Of = Line;
    x0: *f32,
    y0: *f32,
    x1: *f32,
    y1: *f32,
};

pub const WidthHeight = struct {
    pub const cid = 10;
    w: f32,
    h: f32,
};

pub const WidthHeightView = struct {
    pub const Of = WidthHeight;
    w: *f32,
    h: *f32,
};

const rl = @import("../rl.zig").rl;
