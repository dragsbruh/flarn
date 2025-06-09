const std = @import("std");

const TrainType = @import("modelfile.zig").TrainType;

pub const FileFeeder = struct {
    file: std.fs.File,
    file_size: usize,

    fed_count: usize,

    buffer: []u8,
    buffer_size: usize,
    buffer_position: usize,

    train_type: TrainType,

    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        buffer_size: usize,
        train_type: TrainType,
    ) !FileFeeder {
        const file = try std.fs.cwd().openFile(path, .{});
        const buffer = try allocator.alloc(u8, buffer_size);

        var self = FileFeeder{
            .file = file,
            .file_size = @intCast(try file.getEndPos()),

            .fed_count = 0,

            .buffer = buffer,
            .buffer_size = buffer_size,
            .buffer_position = 0,

            .train_type = train_type,
        };
        _ = try self.fill_buffer();
        return self;
    }

    /// returns false if there is nothing more to read
    fn fill_buffer(self: *FileFeeder) !bool {
        self.buffer_position = 0;
        const read = try self.file.read(self.buffer);
        self.buffer_size = read;
        return read != 0;
    }

    pub fn next(self: *FileFeeder) !?u8 {
        if (self.buffer_position >= self.buffer_size) {
            if (!try self.fill_buffer()) return null;
        }

        self.fed_count += 1;

        defer self.buffer_position += 1;

        const char = self.buffer[self.buffer_position];

        if (self.train_type == .newline and char == '\n') {
            return 0;
        } else if (self.train_type == .word and char == ' ') {
            return 0;
        } else return char;
    }

    pub fn deinit(self: *FileFeeder, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        self.file.close();
    }
};
