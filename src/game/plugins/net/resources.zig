pub const PlayerInput = struct {
    current: Values = .zero(),
    ring_buffer: container.RingBuffer(Values),
    gpa: mem.Allocator,

    // save inputs for 16 ticks: 15 * 1/30 ~ .5 secs
    const RING_BUFFER_SIZE = 16;

    const Self = @This();

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .ring_buffer = try .init(gpa, RING_BUFFER_SIZE),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ring_buffer.deinit(self.gpa);
    }

    pub fn queue(self: *Self, input: Values) void {
        self.current = input;
        self.ring_buffer.queue(input);
    }

    pub fn dequeue(self: *Self) ?Values {
        return self.ring_buffer.dequeue();
    }
};

pub const Values = struct {
    tick: u32,
    move: xmath.Vec2,

    pub fn zero() @This() {
        return .{ .tick = 0, .move = .{ .x = 0, .y = 0 } };
    }
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
const xmath = engine.math;
const container = engine.container;
