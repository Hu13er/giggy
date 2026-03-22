// TBC: send help.
// Protocol:
//
// [T: u32 - Client's tick number]
// [VX: f32 - Client's movement in x axis]
// [VY: f32 - Client's movement in y axis]

pub fn writeInput(writer: *Writer, values: *const input_plugin.resources.Values) !void {
    // TODO: To be continued. We need your help dear contributor.
    // We're busy tiling maps. No one's left to do the coding.
    // We've already composed the music. But the game itself is not done yet.
    try writer.writeInt(u32, values.tick, .little);
    try writer.writeInt(u32, @bitCast(values.move.x), .little);
    try writer.writeInt(u32, @bitCast(values.move.y), .little);
}

pub fn readInput(reader: *Reader, values: *input_plugin.resources.Values) !void {
    const tick = try reader.takeInt(u32, .little);
    const x = blk: {
        const tmp = try reader.takeInt(u32, .little);
        break :blk @as(f32, @bitCast(tmp));
    };
    const y = blk: {
        const tmp = try reader.takeInt(u32, .little);
        break :blk @as(f32, @bitCast(tmp));
    };

    values.*.tick = tick;
    values.*.move.x = x;
    values.*.move.y = y;
}

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Writer = std.io.Writer;
const Reader = std.io.Reader;

const engine = @import("engine");
const ecs = engine.ecs;
const wire = engine.net.wire;

const game = @import("game");
const input_plugin = game.plugins.input;
