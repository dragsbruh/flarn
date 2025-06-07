const io = @import("io.zig");
const std = @import("std");
const markov = @import("markov.zig");
const Modelfile = @import("modelfile.zig");

const FileFeeder = @import("feed.zig").FileFeeder;
const interactive = @import("interactive.zig").interactive;

const DOCS_URL = "https://github.com/dragsbruh/flarn";

const Command = enum {
    help,
    train,
    run,
    it,
    docs,
};

pub fn start(allocator: std.mem.Allocator) anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try io.stderr.print("error: expected a command. see `help` command for more info.\n", .{});
        return error.Exit;
    }

    const executable = args[0];
    const command_str = args[1];
    const command_args = args[2..];

    const command = std.meta.stringToEnum(Command, command_str) orelse {
        try io.stderr.print("error: unknown command, received `{s}`.\nsee `help` command for list of available commands..\n", .{command_str});
        return error.Exit;
    };

    return switch (command) {
        .help => Commands.help(executable, command_args),
        .train => Commands.train(allocator, command_args),
        .run => Commands.run(allocator, command_args),
        .docs => Commands.docs(allocator),
        .it => interactive(allocator, command_args),
    };
}

const Commands = struct {
    pub fn help(exe: []const u8, _: []const []const u8) !void {
        try io.stdout.print(
            \\usage:
            \\  {s} <command> [...args]
            \\available commands:
            \\  help                                displays this help message
            \\  train <modelfile> <outfile>         trains a model from modelfile and saves to outfile
            \\  run <model>                         runs a pretrained markov model (.flrn)
            \\  it <model>                          runs flarn in interactive mode (not intended for cli usage, but as an api)
            \\  docs                                opens the github repository in a web browser
            \\
            \\
            // intended extra newline
        , .{exe});
    }

    pub fn train(allocator: std.mem.Allocator, args: []const []const u8) !void {
        if (args.len != 2) {
            try io.stderr.print("error: expected argument modelfile and argument outfile for command `train`\n", .{});
            return error.Exit;
        }
        const modelfile_path = args[0];
        const outfile_path = args[1];

        var modelfile = try Modelfile.load(allocator, modelfile_path);
        defer modelfile.deinit(allocator);

        var chain = markov.Chain.init(modelfile.depth);
        defer chain.deinit(allocator);

        var bar = std.Progress.start(.{
            .root_name = "training model",
            .estimated_total_items = modelfile.paths.items.len,
        });

        for (modelfile.paths.items) |path| {
            const bar_name = try std.fmt.allocPrint(allocator, "training on `{s}`...", .{path});
            defer allocator.free(bar_name);

            var child_bar = bar.start(bar_name, 0);
            defer child_bar.end();

            var feed = try FileFeeder.init(
                allocator,
                path,
                modelfile.buffer_size,
            );
            defer feed.deinit(allocator);

            child_bar.setEstimatedTotalItems(feed.file_size);

            const seq = try allocator.alloc(u8, chain.depth);
            defer allocator.free(seq);

            while (try chain.train(allocator, &feed, seq)) |_| {
                child_bar.completeOne();
            }
        }

        bar.setEstimatedTotalItems(0);
        const serialize_bar = bar.start("serializing", chain.nodes.items.len);

        const file = try std.fs.cwd().createFile(outfile_path, .{});
        defer file.close();

        const serializer = chain.serialize(file.writer().any());

        try serializer.write_header(chain);
        for (chain.nodes.items) |node| {
            try serializer.write_node(node);
            serialize_bar.completeOne();
        }
        try serializer.write_footer();

        serialize_bar.end();
    }

    pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
        if (args.len != 1) {
            try io.stderr.print("error: expected argument pretrained model path for command `run`\n", .{});
            return error.Exit;
        }

        const model_path = args[0];

        const file = std.fs.cwd().openFile(model_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try io.stderr.print("error: pretrained model {s} not found\n", .{model_path});
                return error.Exit;
            },
            else => return err,
        };
        defer file.close();

        var status: []const u8 = undefined;
        var chain = try markov.Chain.deserialize(allocator, file.reader().any(), &status);
        defer chain.deinit(allocator);

        const sequence = try chain.random_sequence(allocator);
        defer allocator.free(sequence);

        while (try chain.generate(sequence)) |byte| {
            std.debug.print("{c}", .{byte});
            chain.shift(sequence, byte);
        }
    }

    pub fn docs(allocator: std.mem.Allocator) !void {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "xdg-open", DOCS_URL },
        }) catch |err| {
            try io.stderr.print("failed to open url {s}: {any}\n", .{ DOCS_URL, err });
            return err;
        };

        if (result.term != .Exited or result.term.Exited != 0) {
            try io.stderr.print("xdg-open failed: {}\nurl is {s}\n", .{ result.term, DOCS_URL });
        }
    }
};
