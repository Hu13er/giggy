pub const ComponentRegistry = struct {
    components: std.AutoArrayHashMap(u32, MultiField.Meta),
    gpa: mem.Allocator,

    const Self = @This();
    pub const Error = error{
        CidAlreadyExists,
    };

    pub fn init(gpa: mem.Allocator) !Self {
        return .{
            .components = .init(gpa),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Self) void {
        const vals = self.components.values();
        for (vals) |*v| v.deinit(self.gpa);
        self.components.deinit();
    }

    pub fn register(self: *Self, comptime C: type) !void {
        comptime util.assertComponent(C);
        const cid = util.cidOf(C);
        if (self.components.contains(cid)) return Error.CidAlreadyExists;
        var meta: MultiField.Meta = try .init(C, self.gpa);
        errdefer meta.deinit(self.gpa);
        try self.components.putNoClobber(cid, meta);
    }

    pub fn registerAllComponents(self: *Self, comptime Ts: []const type) !usize {
        var count: usize = 0;
        inline for (Ts) |T| {
            inline for (comptime std.meta.declarations(T)) |decl| {
                const C = blk: {
                    const MaybeComponent = @field(T, decl.name);
                    if (comptime util.isView(MaybeComponent)) continue;
                    if (comptime !util.isComponent(MaybeComponent)) continue;
                    break :blk MaybeComponent;
                };
                try self.register(C);
                count += 1;
            }
        }
        return count;
    }

    pub fn get(self: *const Self, comptime T: type) *const MultiField.Meta {
        return self.getOrNull(T).?;
    }

    pub fn getOrNull(self: *const Self, comptime T: type) ?*const MultiField.Meta {
        const cid = comptime util.cidOf(T);
        return self.components.getPtr(cid);
    }

    pub fn getByCid(self: *const Self, cid: u32) *const MultiField.Meta {
        return self.getByCidOrNull(cid).?;
    }

    pub fn getByCidOrNull(self: *const Self, cid: u32) ?*const MultiField.Meta {
        return self.components.getPtr(cid);
    }
};

const std = @import("std");
const mem = std.mem;

const util = @import("util.zig");
const MultiField = @import("multi_field.zig").MultiField;
