pub fn levelSystem(app: *core.App) !void {
    const assets_mgr = app.getResource(engine.assets.AssetManager).?;
    const room_mgr = app.getResource(resources.RoomManager).?;
    const registry = app.getResource(engine_prefabs.Registry).?;

    if (assets_mgr.configValuePath("levels", &.{"spawn"})) |spawn| {
        room_mgr.current = resources.roomIdFromName(spawn.string);
    }

    const rooms = assets_mgr.configValuePath("levels", &.{"rooms"}).?;
    var it = rooms.object.iterator();
    while (it.next()) |lvl_entry| {
        var parsed = try engine_prefabs.Registry.loadTiledJson(
            std.heap.page_allocator,
            lvl_entry.value_ptr.*.string,
        );
        defer parsed.deinit();
        try registry.spawnFromTiledValue(app, parsed.value, lvl_entry.key_ptr.*);
    }
}

pub fn doorSystem(app: *core.App) !void {
    const fade = app.getResource(fade_resources.ScreenFade).?;

    var it = app.world.query(&[_]type{
        components.player.Player,
        components.transform.Position,
        components.transform.Velocity,
        components.world.Room,
    });
    while (it.next()) |_| {
        const pos = it.get(components.transform.PositionView);
        const vel = it.get(components.transform.VelocityView);
        const room = it.get(components.world.RoomView);

        if (fade.active()) continue;

        var it_door = app.world.query(&[_]type{
            components.world.Teleport,
            components.transform.Position,
            components.collision.ColliderCircle,
            components.world.Room,
        });
        it_door = it_door;
        while (it_door.next()) |_| {
            const tp = it_door.get(components.world.TeleportView);
            const tp_pos = it_door.get(components.transform.PositionView);
            const tp_col = it_door.get(components.collision.ColliderCircleView);
            const tp_room = it_door.get(components.world.RoomView);

            if (room.id.* != tp_room.id.*) continue;

            if (rl.CheckCollisionPointCircle(
                .{ .x = pos.x.*, .y = pos.y.* },
                .{ .x = tp_pos.x.*, .y = tp_pos.y.* },
                tp_col.radius.*,
            )) {
                vel.x.* = 0;
                vel.y.* = 0;

                const Callback = struct {
                    app: *core.App,
                    room_id: u32,
                    spawn_id: u8,

                    fn call(self: @This()) void {
                        const room_mgr = self.app.getResource(resources.RoomManager).?;
                        const player_entity = self.app.getResource(game.plugins.player.resources.Player).?.entity;

                        if (self.app.world.get(components.world.RoomView, player_entity)) |r| {
                            r.id.* = self.room_id;
                            room_mgr.current = self.room_id;
                        }
                        if (self.app.world.get(components.player.PlayerView, player_entity)) |pl| {
                            pl.just_spawned.* = true;
                            pl.spawn_id.* = self.spawn_id;
                        }
                        if (self.app.world.get(components.transform.VelocityView, player_entity)) |v| {
                            v.x.* = 0;
                            v.y.* = 0;
                        }
                    }
                };
                const ctx = Callback{
                    .app = app,
                    .room_id = tp.room_id.*,
                    .spawn_id = tp.spawn_id.*,
                };
                try fade.begin(app.gpa, ctx, Callback.call);

                break;
            }
        }
    }
}

const std = @import("std");

const engine = @import("engine");
const core = engine.core;
const rl = engine.raylib;
const engine_prefabs = engine.prefabs;

const game = @import("game");
const components = game.components;
const resources = game.plugins.level.resources;
const fade_resources = game.plugins.fade.resources;
