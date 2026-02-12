pub const blobs = @import("blob/main.zig");
pub const ecs_stress = @import("ecs_stress/main.zig");
pub const path_finding = @import("path_finding/main.zig");

test {
    _ = blobs;
    _ = path_finding;
}
