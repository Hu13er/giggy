pub fn renderHealthSystem(app: *core.App) !void {
    const asset_mgr = app.getResource(engine.assets.AssetManager).?;
    const time_res = app.getResource(core.Time).?;
    const bar_res = app.getResource(resources.BarResource).?;
    const screen_res = app.getResource(game.plugins.core.resources.Screen).?;
    const player_res = app.getResource(game.plugins.player.resources.Player)
                    orelse return;

    const screen_height = @as(f32, @floatFromInt(screen_res.height));

    const scale = 0.6;
    if (asset_mgr.textures.get("hud/back1")) |texture| {
        const pos = rl.Vector2{
            .x = 0,
            .y = screen_height - @as(f32, @floatFromInt(texture.height))*scale,
        };
        rl.DrawTextureEx(texture, pos, 0.0, scale, rl.WHITE);
    }

    const offset = 12 * scale;
    if (asset_mgr.textures.get("hud/back2")) |texture| {
        const pos = rl.Vector2{
            .x = offset,
            .y = screen_height - @as(f32, @floatFromInt(texture.height))*scale - offset,
        };
        const color = rl.ColorAlpha(rl.WHITE, 0.3);
        rl.DrawTextureEx(texture, pos, 0.0, scale, color);
    }

    const conv_coefficient = 5.0;
    if (app.world.get(game.components.player.HealthView, player_res.entity)) |health| {
        if (asset_mgr.textures.get("hud/fill")) |texture| {
            const new_perc = @as(f32, @floatFromInt(health.value.*)) /
                            @as(f32, @floatFromInt(health.max_value.*));
            if (@abs(bar_res.current_perc - new_perc) < 0.005) {
                bar_res.current_perc = new_perc;
            } else {
                const t = std.math.clamp(
                    time_res.dt * conv_coefficient,
                    0.0,
                    1.0,
                );
                bar_res.current_perc += (new_perc - bar_res.current_perc) * t;
            }
            const src = rl.Rectangle{
                .x = 0,
                .y = @as(f32, @floatFromInt(texture.height)) * (1 - bar_res.current_perc),
                .width = @as(f32, @floatFromInt(texture.width)),
                .height = @as(f32, @floatFromInt(texture.height)) * bar_res.current_perc,
            };
            const dst = rl.Rectangle{
                .x = offset,
                .y = screen_height - src.height*scale - offset,
                .width = src.width * scale,
                .height = src.height * scale,
            };
            const red = rl.Color{.r = 160, .g = 0, .b = 0, .a = 0};
            const color = rl.ColorAlpha(red, 0.9);
            // rl.DrawTextureEx(texture, pos, 0.0, scale, color);
            rl.DrawTexturePro(texture, src, dst, .{ .x = 0, .y = 0 }, 0.0, color);
        }
    }

    if (asset_mgr.textures.get("hud/shadow")) |texture| {
        const pos = rl.Vector2{
            .x = offset,
            .y = screen_height - @as(f32, @floatFromInt(texture.height))*scale - offset,
        };
        rl.DrawTextureEx(texture, pos, 0.0, scale, rl.WHITE);
    }

    if (asset_mgr.textures.get("hud/highlight")) |texture| {
        const pos = rl.Vector2{
            .x = offset,
            .y = screen_height - @as(f32, @floatFromInt(texture.height))*scale - offset,
        };
        rl.DrawTextureEx(texture, pos, 0.0, scale, rl.WHITE);
    }

    if (asset_mgr.textures.get("hud/border")) |texture| {
        const pos = rl.Vector2{
            .x = 0,
            .y = screen_height - @as(f32, @floatFromInt(texture.height))*scale,
        };
        rl.DrawTextureEx(texture, pos, 0.0, scale, rl.WHITE);
    }
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;

const game = @import("game");
const resources = game.plugins.hud.resources;
