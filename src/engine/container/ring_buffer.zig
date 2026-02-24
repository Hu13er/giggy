pub fn RingBuffer(comptime T: type) type {
    return struct {
        buffer: []T,
        next_write: u32 = 0,
        next_read: u32 = 0,
        need_free: bool = true,

        const Self = @This();

        pub fn init(gpa: mem.Allocator, size: usize) !Self {
            return .{ .buffer = gpa.alloc(T, size) };
        }

        pub fn initBuffered(buffer: []T) Self {
            return .{ .buffer = buffer, .need_free = false };
        }

        pub fn deinit(self: *Self, gpa: mem.Allocator) void {
            if (self.need_free) gpa.free(self.buffer);
        }

        pub fn queue(self: *Self, item: T) void {
            const idx: usize = @intCast(self.next_write % self.buffer.len);
            self.buffer[idx] = item;
            self.next_write +%= 1;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.next_read == self.next_write) return null;
            const idx: usize = @intCast(self.next_read % self.buffer.len);
            return self.buffer[idx];
        }
    };
}

test "RingBuffer get after wrap is not empty" {
    var storage: [4]u8 = [_]u8{0} ** 4;
    var rb = RingBuffer(u8).initBuffered(storage[0..]);
    const max = std.math.maxInt(u32);
    rb.next_read = max - 1;
    rb.next_write = rb.next_read +% 2;

    const idx: usize = @intCast(rb.next_read % rb.buffer.len);
    rb.buffer[idx] = 123;

    try std.testing.expectEqual(@as(?u8, 123), rb.dequeue());
}

const std = @import("std");
const mem = std.mem;
