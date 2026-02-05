const examples = @import("examples.zig");
const game = @import("main.zig");

pub fn main() !void {
    try game.main();
}
