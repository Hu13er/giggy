pub const SampleResource = struct {
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) Self {
        return .{
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

const std = @import("std");
const mem = std.mem;

const engine = @import("engine");
