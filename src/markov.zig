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

    pub fn train(self: *Chain, allocator: std.mem.Allocator, feed: *FileFeeder) !void {
        const seq = try allocator.alloc(u8, self.depth);
        defer allocator.free(seq);

        while (try feed.next()) |byte| {
            const node = try self.get_create_node(allocator, seq);
            try node.incrementWeight(allocator, byte);
            self.shift(seq, byte);
        }
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

    pub fn deinit(self: *Chain, allocator: std.mem.Allocator) void {
        for (self.nodes.items) |node| node.deinit(allocator);
        self.nodes.deinit(allocator);
    }
};

const std = @import("std");
const FileFeeder = @import("feed.zig").FileFeeder;
