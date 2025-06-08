const std = @import("std");
const io = @import("io.zig");
const markov = @import("markov.zig");

const DEFAULT_TOKEN_SIZE = 4;

pub fn open_model(allocator: std.mem.Allocator, path: []const u8) !markov.Chain {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try io.stderr.print("error: unable to open file: {any}`\n", .{err});
        return error.Exit;
    };
    defer file.close();

    var status: []const u8 = undefined;
    const chain = markov.Chain.deserialize(allocator, file.reader().any(), &status) catch |err| switch (err) {
        error.InvalidFormat => {
            try io.stderr.print("error: unable to parse model: {s}`\n", .{status});
            return error.Exit;
        },
        else => return err,
    };

    return chain;
}

const Task = struct {
    sequence: []u8,
};

pub fn interactive(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len != 1) {
        try io.stderr.print("error: expected argument pretrained model for command `it`\n", .{});
        return error.Exit;
    }

    try io.stderr.print("warning: this is not intended to be use in cli manually.\n", .{});

    var chain = try open_model(allocator, args[0]);
    defer chain.deinit(allocator);

    var tasks = std.AutoHashMapUnmanaged(usize, Task).empty;
    defer {
        var iter = tasks.valueIterator();
        while (iter.next()) |task| allocator.free(task.*.sequence);
        tasks.deinit(allocator);
    }

    var pollFds = [_]std.os.linux.pollfd{
        .{ .fd = 0, .events = std.os.linux.POLL.IN, .revents = 0 },
    };

    var token_buffer = try allocator.alloc(u8, DEFAULT_TOKEN_SIZE);
    defer allocator.free(token_buffer);

    var throttle: usize = 0;

    while (true) {
        var timeout: i32 = 10;
        if (tasks.count() > 0) timeout = 0;
        const n = std.os.linux.poll(&pollFds, 1, timeout);
        if (n > 0 and (pollFds[0].revents & std.os.linux.POLL.IN) != 0) {
            const line = try io.stdin.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
            defer allocator.free(line);

            var parts = std.mem.splitScalar(u8, line, '|');
            const command_str = parts.first();

            var arguments = std.ArrayListUnmanaged([]const u8).empty;
            defer arguments.deinit(allocator);

            while (parts.next()) |arg| try arguments.append(allocator, arg);

            const command = std.meta.stringToEnum(Command, command_str) orelse {
                try io.stderr.print("error: {s} is not a valid command\n", .{command_str});
                continue;
            };

            // for now, only one argument that is id
            if (arguments.items.len != 1) {
                try io.stderr.print("error: expected one integer argument\n", .{});
                continue;
            }

            const target = std.fmt.parseInt(usize, arguments.items[0], 10) catch {
                try io.stderr.print("error: invalid integer for argument id: {s}\n", .{arguments.items[0]});
                continue;
            };

            switch (command) {
                .c => {
                    if (tasks.contains(target)) {
                        try io.stderr.print("error: task with id {d} already exists\n", .{target});
                        continue;
                    }

                    const seq = try chain.random_sequence(allocator);
                    try tasks.put(allocator, target, Task{
                        .sequence = seq,
                    });
                    try io.stdout.print("c|{d}\n", .{target});
                },
                .s => {
                    if (tasks.getPtr(target)) |task| {
                        allocator.free(task.*.sequence);
                        _ = tasks.remove(target);
                        try io.stdout.print("s|{d}\n", .{target});
                    }
                },
                .t => {
                    token_buffer = try allocator.realloc(token_buffer, target);
                    try io.stdout.print("t|{d}\n", .{target});
                },
                .l => {
                    throttle = target;
                    try io.stdout.print("l|{d}\n", .{target});
                },
            }
        }

        var iter = tasks.iterator();
        while (iter.next()) |entry| {
            var valid: usize = 0;
            var finished = false;

            for (0..token_buffer.len) |i| {
                const maybe_byte = try chain.generate(entry.value_ptr.*.sequence);

                if (maybe_byte) |byte| {
                    valid += 1;
                    token_buffer[i] = byte;
                    chain.shift(entry.value_ptr.*.sequence, byte);
                } else {
                    finished = true;
                    break;
                }
            }

            try io.stdout.print("n|{d}|", .{entry.key_ptr.*});
            try escapeString(io.stdout, token_buffer[0..valid]);
            try io.stdout.writeByte('\n');

            if (finished) {
                try io.stdout.print("s|{d}\n", .{entry.key_ptr.*});
                allocator.free(entry.value_ptr.*.sequence);
                _ = tasks.remove(entry.key_ptr.*);
            }
        }

        if (throttle != 0) {
            std.Thread.sleep(1000 * 1000 * throttle);
        }
    }
}

const Command = enum {
    c, // create
    s, // stop
    t, // set token size (default 4)
    l, // throttle
};

pub fn escapeString(writer: anytype, input: []const u8) !void {
    const hex = "0123456789abcdef";

    for (input) |c| {
        if (c < 0x20) {
            try writer.writeAll("\\u00");
            try writer.writeByte(hex[(c >> 4) & 0xF]);
            try writer.writeByte(hex[c & 0xF]);
        } else {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                '|' => try writer.writeAll("\\|"),
                else => try writer.writeByte(c),
            }
        }
    }
}
