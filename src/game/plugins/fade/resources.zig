pub const ScreenFade = struct {
    state: State = .idle,
    t: f32 = 0,
    alpha: f32 = 0, // 0..1

    out_duration: f32 = 0.20,
    hold_duration: f32 = 0.05,
    in_duration: f32 = 0.20,

    callback: ?Callback = null,

    pub const Callback = struct {
        alloc: mem.Allocator,
        ctx: *anyopaque,
        call_fn: *const fn (ctx: *anyopaque) void,
        destroy_fn: *const fn (alloc: mem.Allocator, ctx: *anyopaque) void,

        pub fn init(alloc: mem.Allocator, context: anytype, func: fn (ctx: @TypeOf(context)) void) !@This() {
            const T = @TypeOf(context);
            const ptr = try alloc.create(T);
            ptr.* = context;
            return Callback{
                .alloc = alloc,
                .ctx = ptr,
                .call_fn = struct {
                    fn inner(c: *anyopaque) void {
                        const p: *T = @ptrCast(@alignCast(c));
                        func(p.*);
                    }
                }.inner,
                .destroy_fn = struct {
                    fn inner(a: mem.Allocator, c: *anyopaque) void {
                        const p: *T = @ptrCast(@alignCast(c));
                        a.destroy(p);
                    }
                }.inner,
            };
        }

        pub fn call(self: @This()) void {
            self.call_fn(self.ctx);
        }

        pub fn destroy(self: @This()) void {
            self.destroy_fn(self.alloc, self.ctx);
        }
    };

    pub const State = enum {
        idle,
        fading_out,
        hold_black,
        fading_in,
    };

    pub fn active(self: *const @This()) bool {
        return self.state != .idle;
    }

    pub fn begin(
        self: *@This(),
        gpa: mem.Allocator,
        ctx: anytype,
        func: fn (_: @TypeOf(ctx)) void,
    ) !void {
        // Ignore requests while already transitioning.
        if (self.state != .idle) return;
        self.callback = try .init(gpa, ctx, func);
        self.state = .fading_out;
        self.t = 0;
        self.alpha = 0;
    }
};

const std = @import("std");
const mem = std.mem;
