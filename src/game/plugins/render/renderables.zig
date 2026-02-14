pub const Renderable = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    texture: rl.Texture,
    flip_h: bool,
    z_index: i16,
};

pub const RenderableList = std.ArrayList(Renderable);

const std = @import("std");
const rl = @import("engine").rl;
