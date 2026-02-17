pub const Scheduler = struct {
    startup: StepSchedule,
    fixed_update: StepSchedule,
    update: StepSchedule,
    render: StepSchedule,
    fixed_dt: f32,
    accumulator: f32,
    startup_ran: bool,
    dirty: bool,
    gpa: mem.Allocator,

    const Self = @This();
    pub const SystemFn = *const fn (*App) anyerror!void;
    pub const SystemConfig = struct {
        id: ?[]const u8 = null,
        provides: []const []const u8 = &.{},
        after_ids: []const []const u8 = &.{},
        after_ids_optional: []const []const u8 = &.{},
        after_all_labels: []const []const u8 = &.{},
    };
    pub const Step = enum {
        startup,
        fixed_update,
        update,
        render,
    };

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .startup = .{},
            .fixed_update = .{},
            .update = .{},
            .render = .{},
            .gpa = gpa,
            .fixed_dt = 1.0 / 60.0,
            .accumulator = 0,
            .startup_ran = false,
            .dirty = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.startup.deinit(self.gpa);
        self.fixed_update.deinit(self.gpa);
        self.update.deinit(self.gpa);
        self.render.deinit(self.gpa);
    }

    pub fn add(self: *Self, step: Step, run: SystemFn, config: SystemConfig) !void {
        const desc = SystemDesc{
            .id = config.id,
            .run = run,
            .provides = config.provides,
            .after_ids = config.after_ids,
            .after_ids_optional = config.after_ids_optional,
            .after_all_labels = config.after_all_labels,
        };
        switch (step) {
            .startup => try self.startup.add(self.gpa, desc),
            .fixed_update => try self.fixed_update.add(self.gpa, desc),
            .update => try self.update.add(self.gpa, desc),
            .render => try self.render.add(self.gpa, desc),
        }
        self.dirty = true;
    }

    pub fn runStep(self: *Self, step: Step, app: *App) !void {
        if (self.dirty) {
            try self.finalize();
        }
        const list = switch (step) {
            .startup => self.startup.compiled.items,
            .fixed_update => self.fixed_update.compiled.items,
            .update => self.update.compiled.items,
            .render => self.render.compiled.items,
        };
        for (list) |system| {
            try system(app);
        }
    }

    pub fn setFixedDelta(self: *Self, fixed_dt: f32) void {
        self.fixed_dt = fixed_dt;
    }

    pub fn tick(self: *Self, app: *App, dt: f32) !void {
        if (self.dirty) {
            try self.finalize();
        }
        const time = app.getResource(Time);
        if (!self.startup_ran) {
            if (time) |t| {
                t.*.dt = 0;
                t.*.fixed_dt = self.fixed_dt;
                t.*.alpha = 0;
            }
            try self.runStep(.startup, app);
            self.startup_ran = true;
        }

        self.accumulator += dt;
        while (self.accumulator >= self.fixed_dt) : (self.accumulator -= self.fixed_dt) {
            if (time) |t| {
                t.*.dt = self.fixed_dt;
                t.*.fixed_dt = self.fixed_dt;
                t.*.alpha = 0;
            }
            try self.runStep(.fixed_update, app);
        }

        if (time) |t| {
            t.*.dt = dt;
            t.*.fixed_dt = self.fixed_dt;
            t.*.alpha = if (self.fixed_dt > 0) xmath.clamp01(self.accumulator / self.fixed_dt) else 0;
        }
        try self.runStep(.update, app);
        try self.runStep(.render, app);
    }

    pub fn finalize(self: *Self) !void {
        if (!self.dirty) return;
        try self.startup.compile(self.gpa);
        try self.fixed_update.compile(self.gpa);
        try self.update.compile(self.gpa);
        try self.render.compile(self.gpa);
        self.dirty = false;
    }

    pub const SystemDesc = struct {
        id: ?[]const u8,
        run: SystemFn,
        provides: []const []const u8,
        after_ids: []const []const u8,
        after_ids_optional: []const []const u8,
        after_all_labels: []const []const u8,
    };

    const StepSchedule = struct {
        systems: std.ArrayListUnmanaged(SystemDesc) = .{},
        compiled: std.ArrayListUnmanaged(SystemFn) = .{},

        pub fn deinit(self: *StepSchedule, gpa: mem.Allocator) void {
            self.systems.deinit(gpa);
            self.compiled.deinit(gpa);
        }

        pub fn add(self: *StepSchedule, gpa: mem.Allocator, desc: SystemDesc) !void {
            try self.systems.append(gpa, desc);
        }

        pub fn compile(self: *StepSchedule, gpa: mem.Allocator) !void {
            self.compiled.clearRetainingCapacity();
            var graph = graph_mod.Graph.init(gpa);
            defer graph.deinit();

            const system_count = self.systems.items.len;
            for (0..system_count) |_| {
                _ = try graph.addNode();
            }

            var id_map = std.StringHashMapUnmanaged(usize){};
            defer id_map.deinit(gpa);

            for (self.systems.items, 0..) |system, index| {
                if (system.id) |id| {
                    if (id_map.contains(id)) return error.DuplicateSystemId;
                    try id_map.put(gpa, id, index);
                }
            }

            var label_map = std.StringHashMapUnmanaged(std.ArrayListUnmanaged(usize)){};
            defer {
                var it = label_map.valueIterator();
                while (it.next()) |list| {
                    list.deinit(gpa);
                }
                label_map.deinit(gpa);
            }

            for (self.systems.items, 0..) |system, index| {
                for (system.provides) |label| {
                    const entry = try label_map.getOrPut(gpa, label);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = .{};
                    }
                    try entry.value_ptr.append(gpa, index);
                }
            }

            for (self.systems.items, 0..) |system, index| {
                for (system.after_ids) |dep_id| {
                    const dep_index = id_map.get(dep_id) orelse return error.MissingSystemId;
                    try graph.addEdge(dep_index, index);
                }
                for (system.after_ids_optional) |dep_id| {
                    if (id_map.get(dep_id)) |dep_index| {
                        try graph.addEdge(dep_index, index);
                    }
                }
                for (system.after_all_labels) |label| {
                    if (label_map.get(label)) |providers| {
                        for (providers.items) |provider| {
                            try graph.addEdge(provider, index);
                        }
                    }
                }
            }

            var order = try graph.topoSort(gpa);
            defer order.deinit(gpa);

            try self.compiled.ensureTotalCapacity(gpa, system_count);
            for (order.items) |index| {
                try self.compiled.append(gpa, self.systems.items[index].run);
            }
        }
    };

};

test "scheduler orders by dependencies and labels" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var scheduler = Scheduler.init(alloc);
    defer scheduler.deinit();

    try scheduler.add(.render, schedulerTestPass2System, .{
        .provides = &.{"pass"},
        .after_all_labels = &.{"begin"},
    });
    try scheduler.add(.render, schedulerTestBeginSystem, .{
        .provides = &.{"begin"},
    });
    try scheduler.add(.render, schedulerTestEndSystem, .{
        .after_all_labels = &.{"pass"},
    });
    try scheduler.add(.render, schedulerTestPass1System, .{
        .provides = &.{"pass"},
        .after_all_labels = &.{"begin"},
    });

    try scheduler.finalize();
    const list = scheduler.render.compiled.items;
    try testing.expectEqual(@as(usize, 4), list.len);
    try testing.expectEqual(schedulerTestBeginSystem, list[0]);
    try testing.expectEqual(schedulerTestPass2System, list[1]);
    try testing.expectEqual(schedulerTestPass1System, list[2]);
    try testing.expectEqual(schedulerTestEndSystem, list[3]);
}

test "scheduler reports missing deps and cycles" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var scheduler_missing = Scheduler.init(alloc);
    defer scheduler_missing.deinit();
    try scheduler_missing.add(.update, schedulerTestMissingDepSystem, .{
        .after_ids = &.{"nope"},
    });
    try testing.expectError(error.MissingSystemId, scheduler_missing.finalize());

    var scheduler_cycle = Scheduler.init(alloc);
    defer scheduler_cycle.deinit();
    try scheduler_cycle.add(.update, schedulerTestASystem, .{
        .id = "a",
        .after_ids = &.{"b"},
    });
    try scheduler_cycle.add(.update, schedulerTestBSystem, .{
        .id = "b",
        .after_ids = &.{"a"},
    });
    try testing.expectError(error.Cycle, scheduler_cycle.finalize());
}

const std = @import("std");
const mem = std.mem;
const engine = @import("engine");
const xmath = engine.math;
const graph_mod = engine.graph;

const App = @import("app.zig").App;
const Time = @import("app.zig").Time;

fn schedulerTestBeginSystem(_: *App) !void {}
fn schedulerTestPass1System(_: *App) !void {}
fn schedulerTestPass2System(_: *App) !void {}
fn schedulerTestEndSystem(_: *App) !void {}
fn schedulerTestMissingDepSystem(_: *App) !void {}
fn schedulerTestASystem(_: *App) !void {}
fn schedulerTestBSystem(_: *App) !void {}
