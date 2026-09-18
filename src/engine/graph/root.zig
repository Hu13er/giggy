const std = @import("std");
const mem = std.mem;

pub const Graph = struct {
    nodes: std.ArrayListUnmanaged(Node),
    gpa: mem.Allocator,

    const Self = @This();

    pub fn init(gpa: mem.Allocator) Self {
        return .{ .nodes = .empty, .gpa = gpa };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| {
            node.outs.deinit(self.gpa);
        }
        self.nodes.deinit(self.gpa);
    }

    pub fn addNode(self: *Self) !usize {
        try self.nodes.append(self.gpa, .{ .outs = .empty });
        return self.nodes.items.len - 1;
    }

    pub fn addEdge(self: *Self, from: usize, to: usize) !void {
        try self.nodes.items[from].outs.append(self.gpa, to);
    }

    pub fn topoSort(self: *const Self, gpa: mem.Allocator) !std.ArrayListUnmanaged(usize) {
        const node_count = self.nodes.items.len;
        var indegree = try gpa.alloc(usize, node_count);
        defer gpa.free(indegree);
        @memset(indegree, 0);

        for (self.nodes.items) |node| {
            for (node.outs.items) |to| {
                indegree[to] += 1;
            }
        }

        var queue = std.ArrayListUnmanaged(usize).empty;
        defer queue.deinit(gpa);
        for (0..node_count) |i| {
            if (indegree[i] == 0) {
                try queue.append(gpa, i);
            }
        }

        var order = std.ArrayListUnmanaged(usize).empty;
        errdefer order.deinit(gpa);
        try order.ensureTotalCapacity(gpa, node_count);

        var head: usize = 0;
        while (head < queue.items.len) {
            const node_index = queue.items[head];
            head += 1;

            try order.append(gpa, node_index);
            for (self.nodes.items[node_index].outs.items) |to| {
                indegree[to] -= 1;
                if (indegree[to] == 0) {
                    var insert_pos = queue.items.len;
                    while (insert_pos > head and queue.items[insert_pos - 1] > to) : (insert_pos -= 1) {}
                    try queue.insert(gpa, insert_pos, to);
                }
            }
        }

        if (order.items.len != node_count) return error.Cycle;
        return order;
    }

    const Node = struct {
        outs: std.ArrayListUnmanaged(usize),
    };
};

test "graph topo sort is stable and detects cycles" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var graph = Graph.init(alloc);
    defer graph.deinit();

    const a = try graph.addNode();
    const b = try graph.addNode();
    const c = try graph.addNode();
    const d = try graph.addNode();

    try graph.addEdge(a, c);
    try graph.addEdge(b, c);
    try graph.addEdge(c, d);

    var order = try graph.topoSort(alloc);
    defer order.deinit(alloc);
    try testing.expectEqualSlices(usize, &.{ a, b, c, d }, order.items);

    var cycle = Graph.init(alloc);
    defer cycle.deinit();
    const n0 = try cycle.addNode();
    const n1 = try cycle.addNode();
    try cycle.addEdge(n0, n1);
    try cycle.addEdge(n1, n0);

    try testing.expectError(error.Cycle, cycle.topoSort(alloc));
}

test {
    _ = std.testing.refAllDecls(@This());
}
