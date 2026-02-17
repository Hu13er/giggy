pub const App = struct {
    world: ecs.World,
    resources: ResourceStore,
    scheduler: Scheduler,
    plugin_set: std.StringHashMap(void),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        var app: Self = .{
            .world = try ecs.World.init(gpa),
            .resources = ResourceStore.init(gpa),
            .scheduler = Scheduler.init(gpa),
            .plugin_set = std.StringHashMap(void).init(gpa),
            .gpa = gpa,
        };
        _ = try app.insertResource(Time, .init());
        return app;
    }

    pub fn deinit(self: *Self) void {
        self.plugin_set.deinit();
        self.scheduler.deinit();
        self.resources.deinit();
        self.world.deinit();
    }

    pub fn addPlugin(self: *Self, comptime P: type, plugin: P) !void {
        comptime assertPlugin(P);
        const name = @typeName(P);
        if (self.plugin_set.contains(name)) return;
        try self.plugin_set.put(name, {});
        try plugin.build(self);
    }

    pub fn addSystem(self: *Self, step: Scheduler.Step, run: Scheduler.SystemFn, config: Scheduler.SystemConfig) !void {
        try self.scheduler.add(step, run, config);
    }

    pub fn runStep(self: *Self, step: Scheduler.Step) !void {
        try self.scheduler.runStep(step, self);
    }

    pub fn setFixedDelta(self: *Self, fixed_dt: f32) void {
        self.scheduler.setFixedDelta(fixed_dt);
    }

    pub fn tick(self: *Self, dt: f32) !void {
        try self.scheduler.tick(self, dt);
    }

    // insertResource gets full ownership of value.
    pub fn insertResource(self: *Self, comptime T: type, value: T) !*T {
        return self.resources.insert(T, value);
    }

    pub fn insertResourceWithDeinit(
        self: *Self,
        comptime T: type,
        value: T,
        deinit_fn: *const fn (*T, mem.Allocator) void,
    ) !*T {
        return self.resources.insertWithDeinit(T, value, deinit_fn);
    }

    pub fn getResource(self: *Self, comptime T: type) ?*T {
        return self.resources.get(T);
    }
};

pub const Time = struct {
    dt: f32,
    fixed_dt: f32,
    alpha: f32,

    pub fn init() Time {
        return .{ .dt = 0, .fixed_dt = 0, .alpha = 0 };
    }
};

pub fn assertPlugin(comptime P: type) void {
    comptime if (!isPlugin(P)) @compileError("expected to be plugin");
}

pub fn isPlugin(comptime P: type) bool {
    return std.meta.hasFn(P, "build");
}

test "App plugins, resources, and scheduler" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var app = try App.init(alloc);
    defer app.deinit();

    var tracker_deinit_called = false;
    try app.addPlugin(TestCounterPlugin, .{ .tracker_deinit_called = &tracker_deinit_called });
    try app.addSystem(.update, testAddOneSystem, .{});
    try app.addSystem(.update, testAddTwoSystem, .{});
    try app.runStep(.update);

    const actual_counter = app.getResource(TestCounter).?;
    try testing.expectEqual(@as(u32, 3), actual_counter.value);
    const removed_tacker = app.resources.remove(TestTracker);
    try testing.expect(removed_tacker);
    try testing.expect(tracker_deinit_called);
}

const std = @import("std");
const mem = std.mem;
const engine = @import("engine");
const ecs = engine.ecs;
const ResourceStore = @import("resources.zig").ResourceStore;
const Scheduler = @import("scheduler.zig").Scheduler;

const TestCounter = struct {
    value: u32,
    pub fn inc(self: *@This(), v: u32) void {
        self.value += v;
    }
};

const TestTracker = struct {
    value: u8,
    deinit_called: *bool,
    pub fn init(deinit_called: *bool) @This() {
        return .{ .value = 0, .deinit_called = deinit_called };
    }
    pub fn deinit(self: *@This()) void {
        self.deinit_called.* = true;
    }
};

const TestCounterPlugin = struct {
    tracker_deinit_called: *bool,

    pub fn build(self: @This(), app: *App) !void {
        _ = try app.insertResource(TestCounter, .{ .value = 0 });
        _ = try app.insertResource(TestTracker, .init(self.tracker_deinit_called));
    }
};

fn testAddOneSystem(app: *App) !void {
    const counter = app.getResource(TestCounter).?;
    counter.inc(1);
}

fn testAddTwoSystem(app: *App) !void {
    const counter = app.getResource(TestCounter).?;
    counter.inc(2);
}
