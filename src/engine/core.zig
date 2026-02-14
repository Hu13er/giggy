pub const app = @import("./core/app.zig");
pub const scheduler = @import("./core/scheduler.zig");
pub const resources = @import("./core/resources.zig");

pub const App = app.App;
pub const Scheduler = scheduler.Scheduler;
pub const ResourceStore = resources.ResourceStore;
pub const Time = app.Time;

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
