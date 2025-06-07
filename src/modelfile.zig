const std = @import("std");
const io = @import("io.zig");

pub const Model = struct {
    depth: usize,
    paths: std.ArrayListUnmanaged([]const u8),
    buffer_size: usize,

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        for (self.paths.items) |path| allocator.free(path);
        self.paths.deinit(allocator);
    }
};

pub fn load(allocator: std.mem.Allocator, modelfile_path: []const u8) !Model {
    const source = std.fs.cwd().readFileAllocOptions(
        allocator,
        modelfile_path,
        std.math.maxInt(usize),
        null,
        @alignOf(u8),
        0,
    ) catch |err| {
        try io.stderr.print("error opening modefile at {s}: {any}\n", .{ modelfile_path, err });
        return error.Exit;
    };
    defer allocator.free(source);

    var status = std.zon.parse.Status{};
    defer status.deinit(allocator);

    const raw_model = std.zon.parse.fromSlice(
        struct {
            depth: usize,
            buffer_size: usize,
            paths: []const []const u8,
        },
        allocator,
        source,
        &status,
        .{},
    ) catch |err| switch (err) {
        error.ParseZon => {
            try io.stderr.print("error: invalid modelfile at {s}:\n", .{modelfile_path});
            try status.format("", .{}, io.stderr);
            return error.Exit;
        },
        else => return err,
    };
    defer std.zon.parse.free(allocator, raw_model);

    var model = Model{
        .depth = raw_model.depth,
        .buffer_size = raw_model.buffer_size,
        .paths = .empty,
    };

    for (raw_model.paths) |path| {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            try io.stderr.print("error: unable to stat file {s}: {any}\n", .{ path, err });
            return error.Exit;
        };
        if (stat.kind == .file) {
            try model.paths.append(allocator, try allocator.dupe(u8, path));
        } else if (stat.kind == .directory) {
            var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
            defer dir.close();

            var walker = try dir.walk(allocator);
            defer walker.deinit();

            while (try walker.next()) |entry| {
                if (entry.kind == .file) {
                    const fullpath = try std.fs.path.join(allocator, &.{ path, entry.path });
                    defer allocator.free(fullpath);
                    try model.paths.append(allocator, try allocator.dupe(u8, fullpath));
                }
            }
        } else {
            return error.Exit;
        }
    }

    return model;
}
