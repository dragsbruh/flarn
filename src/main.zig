const std = @import("std");
const start = @import("flarn.zig").start;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    start(allocator) catch |err| switch (err) {
        error.Exit => return 1,
        else => return err,
    };
    return 0;
}
