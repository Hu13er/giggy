pub fn fadeSystem(app: *core.App) !void {
    const time = app.getResource(core.Time).?;
    const fade = app.getResource(resources.ScreenFade).?;

    switch (fade.state) {
        .idle => fade.alpha = 0,
        .fading_out => {
            const out_dur = @max(fade.out_duration, 0.001);
            fade.t += time.dt;
            fade.alpha = std.math.clamp(fade.t / out_dur, 0, 1);
            if (fade.alpha >= 1) {
                if (fade.callback) |cb| {
                    cb.call();
                    cb.destroy();
                }
                fade.callback = null;
                fade.state = .hold_black;
                fade.t = 0;
                fade.alpha = 1;
            }
        },
        .hold_black => {
            fade.alpha = 1;
            fade.t += time.dt;
            if (fade.t >= fade.hold_duration) {
                fade.state = .fading_in;
                fade.t = 0;
            }
        },
        .fading_in => {
            const in_dur = @max(fade.in_duration, 0.001);
            fade.t += time.dt;
            const k = std.math.clamp(fade.t / in_dur, 0, 1);
            fade.alpha = 1 - k;
            if (k >= 1) {
                fade.state = .idle;
                fade.t = 0;
                fade.alpha = 0;
            }
        },
    }
}

pub fn fadeOverlaySystem(app: *core.App) !void {
    const fade = app.getResource(resources.ScreenFade).?;
    if (fade.alpha <= 0) return;

    const screen = app.getResource(core_resources.Screen).?;
    const a: u8 = @intFromFloat(std.math.clamp(fade.alpha, 0, 1) * 255.0);
    rl.DrawRectangle(
        0,
        0,
        @intCast(screen.width),
        @intCast(screen.height),
        rl.Color{ .r = 0, .g = 0, .b = 0, .a = a },
    );
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const game = @import("game");
const components = game.components;
const resources = game.plugins.fade.resources;
const core_resources = game.plugins.core.resources;
const render = game.plugins.render;
