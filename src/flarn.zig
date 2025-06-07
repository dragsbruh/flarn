const io = @import("io.zig");
const std = @import("std");
const markov = @import("markov.zig");
const Modelfile = @import("modelfile.zig");

const FileFeeder = @import("feed.zig").FileFeeder;

pub fn start(allocator: std.mem.Allocator) anyerror!void {
    var model = try Modelfile.load(allocator, "model.zon");
    defer model.deinit(allocator);

    var chain = markov.Chain.init(model.depth);
    defer chain.deinit(allocator);

    for (model.paths.items) |path| {
        var feed = try FileFeeder.init(allocator, path, model.buffer_size);
        defer feed.deinit(allocator);

        try chain.train(allocator, &feed);
        std.debug.print("\n", .{});
    }

    const sequence = try chain.random_sequence(allocator);
    defer allocator.free(sequence);

    while (try chain.generate(sequence)) |byte| {
        std.debug.print("{c}", .{byte});
        chain.shift(sequence, byte);
    }
}
