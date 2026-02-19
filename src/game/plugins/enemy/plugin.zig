pub const Plugin = struct {
    pub fn build(self: @This(), app: *core.App) !void {
        _ = self;
        _ = app;
    }
};

const engine = @import("engine");
const core = engine.core;
