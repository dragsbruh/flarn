const std = @import("std");
const FileFeeder = @import("feed.zig").FileFeeder;

pub const Node = struct {
    sequence: []const u8,
    weights: std.ArrayListUnmanaged(usize),
    chars: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, sequence: []const u8) !*Node {
        var self = try allocator.create(Node);
        self.sequence = try allocator.dupe(u8, sequence);
        self.weights = .empty;
        self.chars = .empty;
        return self;
    }

    pub fn incrementWeight(self: *Node, allocator: std.mem.Allocator, char: u8) !void {
        for (0..self.chars.items.len) |i| {
            if (char == self.chars.items[i]) {
                self.weights.items[i] += 1;
                return;
            }
        }
        try self.chars.append(allocator, char);
        try self.weights.append(allocator, 1);
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.sequence);
        self.weights.deinit(allocator);
        self.chars.deinit(allocator);
        allocator.destroy(self);
    }
};

pub const Chain = struct {
    nodes: std.ArrayListUnmanaged(*Node) = .empty,
    depth: usize,

    pub fn init(depth: usize) Chain {
        return Chain{ .depth = depth };
    }

    pub fn get_node(self: *Chain, sequence: []const u8) ?*Node {
        // for (self.nodes.items) |node| {
        //     if (std.mem.eql(u8, node.*.sequence, sequence)) {
        //         return node;
        //     }
        // }
        // return null;
        var low: usize = 0;
        var high: usize = self.nodes.items.len;

        while (low < high) {
            const mid = low + (high - low) / 2;
            const node = self.nodes.items[mid];
            const cmp = std.mem.order(u8, sequence, node.sequence);
            switch (cmp) {
                .lt => high = mid,
                .gt => low = mid + 1,
                .eq => return node,
            }
        }

        return null;
    }

    pub fn get_create_node(self: *Chain, allocator: std.mem.Allocator, sequence: []const u8) !*Node {
        const existing = self.get_node(sequence);
        if (existing) |node| return node;

        const node = try Node.init(allocator, sequence);
        const index = self.binary_search_insert_index(sequence);
        try self.nodes.insert(allocator, index, node);
        return node;
    }

    fn binary_search_insert_index(self: Chain, sequence: []const u8) usize {
        var low: usize = 0;
        var high: usize = self.nodes.items.len;

        while (low < high) {
            const mid = low + (high - low) / 2;
            const cmp = std.mem.order(u8, sequence, self.nodes.items[mid].sequence);
            switch (cmp) {
                .lt => high = mid,
                .gt => low = mid + 1,
                .eq => return mid,
            }
        }

        return low;
    }

    pub fn random_sequence(self: *Chain, allocator: std.mem.Allocator) ![]u8 {
        const index = std.crypto.random.intRangeLessThan(usize, 0, self.nodes.items.len);
        return try allocator.dupe(u8, self.nodes.items[index].sequence);
    }

    pub fn train(self: *Chain, allocator: std.mem.Allocator, feed: *FileFeeder, seq: []u8) !?u8 {
        // const seq = try allocator.alloc(u8, self.depth);
        // defer allocator.free(seq);

        if (try feed.next()) |byte| {
            const node = try self.get_create_node(allocator, seq);
            try node.incrementWeight(allocator, byte);
            self.shift(seq, byte);
            return byte;
        }
        return null;
    }

    pub fn generate(self: *Chain, sequence: []const u8) !?u8 {
        const maybe_node = self.get_node(sequence);
        if (maybe_node) |node| {
            const index = std.crypto.random.weightedIndex(usize, node.weights.items);
            return node.chars.items[index];
        }
        return null;
    }

    pub fn shift(_: Chain, seq: []u8, next: u8) void {
        for (1..seq.len) |i| seq[i - 1] = seq[i];
        seq[seq.len - 1] = next;
    }

    pub fn serialize(_: Chain, writer: std.io.AnyWriter) Serializer {
        return Serializer{ .writer = writer };
    }

    pub fn deserialize(allocator: std.mem.Allocator, reader: std.io.AnyReader, status: ?*[]const u8) anyerror!Chain {
        var magic: [4]u8 = undefined;
        _ = try reader.read(&magic);
        if (!std.mem.eql(u8, &magic, "FLRN")) {
            if (status) |status_ptr| status_ptr.* = try allocator.dupe(u8, "expected FLRN magic bytes");
            return error.InvalidFormat;
        }

        const depth = try reader.readInt(usize, .little);
        const node_count = try reader.readInt(usize, .little);

        var nodes = std.ArrayListUnmanaged(*Node).empty;

        for (0..node_count) |i| {
            const chars_count = try reader.readInt(usize, .little);

            const seq_buffer = try allocator.alloc(u8, depth);
            const read = try reader.read(seq_buffer);
            if (read != seq_buffer.len) {
                if (status) |status_ptr| status_ptr.* = try std.fmt.allocPrint(allocator, "unexpected sequence end in node {d}\n", .{i + 1});
                return error.InvalidFormat;
            }

            const chars_buffer = try allocator.alloc(u8, chars_count);
            const chars_read = try reader.read(chars_buffer);
            if (chars_read != chars_buffer.len) {
                if (status) |status_ptr| status_ptr.* = try std.fmt.allocPrint(allocator, "unexpected chars end in node {d}\n", .{i + 1});
                return error.InvalidFormat;
            }

            const weights_buffer = try allocator.alloc(usize, chars_count);
            for (0..chars_count) |ci| {
                weights_buffer[ci] = try reader.readInt(usize, .little);
            }

            const node = try allocator.create(Node);
            node.*.sequence = seq_buffer;
            node.*.chars = std.ArrayListUnmanaged(u8).fromOwnedSlice(chars_buffer);
            node.*.weights = std.ArrayListUnmanaged(usize).fromOwnedSlice(weights_buffer);

            try nodes.append(allocator, node);
        }

        errdefer for (nodes.items) |node| node.*.deinit(allocator);

        var end_buffer: [3]u8 = undefined;
        _ = try reader.read(&end_buffer);
        if (!std.mem.eql(u8, &end_buffer, "END")) {
            if (status) |status_ptr| status_ptr.* = try allocator.dupe(u8, "expected END\n");
            return error.InvalidFormat;
        }

        return Chain{
            .depth = depth,
            .nodes = nodes,
        };
    }

    pub fn deinit(self: *Chain, allocator: std.mem.Allocator) void {
        for (self.nodes.items) |node| node.deinit(allocator);
        self.nodes.deinit(allocator);
    }
};

pub const Serializer = struct {
    writer: std.io.AnyWriter,

    pub fn write_header(self: Serializer, chain: Chain) !void {
        try self.writer.writeAll("FLRN"); // magic bytes, duh
        try self.writer.writeInt(usize, chain.depth, .little);
        try self.writer.writeInt(usize, chain.nodes.items.len, .little);
    }

    pub fn write_node(self: Serializer, node: *Node) !void {
        try self.writer.writeInt(usize, node.*.chars.items.len, .little);
        try self.writer.writeAll(node.*.sequence);
        try self.writer.writeAll(node.*.chars.items);

        for (node.*.weights.items) |weight| {
            try self.writer.writeInt(usize, weight, .little);
        }
    }

    pub fn write_footer(self: Serializer) !void {
        try self.writer.writeAll("END");
    }
};
