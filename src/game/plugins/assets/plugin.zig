pub const Plugin = struct {
    io: std.Io,
    bundle: []const u8 = "resources/bundle.json",

    pub fn build(self: @This(), app: *core.App) !void {
        const assets_mgr = app.getResource(engine.assets.AssetManager).?;
        try assets_mgr.loadBundle(self.bundle);

        if (assets_mgr.models.getPtr("witch")) |witch_model| {
            for (witch_model.model.materials[0..@intCast(witch_model.model.materialCount)]) |*mat| {
                var col = &mat.maps[rl.MATERIAL_MAP_ALBEDO].color;
                col.r = linearToSRGB(col.r);
                col.g = linearToSRGB(col.g);
                col.b = linearToSRGB(col.b);
            }
        }

        if (assets_mgr.models.getPtr("greenman")) |greenman_model| {
            if (assets_mgr.shaders.getPtr("skinning")) |skinning_shader| {
                greenman_model.model.materials[1].shader = skinning_shader.*;
            }
        }
    }
};

fn linearToSRGB(c: u8) u8 {
    const v = @as(f32, @floatFromInt(c)) / 255.0;
    const corrected = std.math.pow(f32, v, 1.0 / 2.2);
    return @intFromFloat(@min(255.0, corrected * 255.0));
}


const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
