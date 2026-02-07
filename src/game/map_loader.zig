pub const Layer = struct {
    points: []Point,
    polygons: []Polygon,
    rectangles: []Rectangle,
    images: []Image,
};

pub const Image = struct {
    name: []const u8,
    position: Vertex,
    width: f32,
    height: f32,
    index: usize,
};

pub const Rectangle = struct {
    name: []const u8,
    position: Vertex,
    width: f32,
    height: f32,
};

pub const Point = struct {
    name: []const u8,
    position: Vertex,
};

pub const Polygon = struct {
    name: []const u8,
    closed: bool,
    vertices: []Vertex,
};

pub const Vertex = struct {
    x: f32,
    y: f32,
};

pub const ParsedLayer = json.Parsed(Layer);

pub fn loadLayer(allocator: std.mem.Allocator, file_path: []const u8) !ParsedLayer {
    var file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, math.maxInt(usize));
    defer allocator.free(contents);

    return try json.parseFromSlice(
        Layer,
        allocator,
        contents,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
}

const std = @import("std");
const fs = std.fs;
const json = std.json;
const mem = std.mem;
const math = std.math;

const ArrayList = std.ArrayList;
