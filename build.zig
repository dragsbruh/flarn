const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "flarn",
        .root_module = exe_mod,
    });

    const git_tag = commandOutput(b, &.{ "git", "describe", "--tags", "--abbrev=0" }, "git tag") catch return;
    const git_commit_hash = commandOutput(b, &.{ "git", "rev-parse", "HEAD" }, "git commit hash") catch return;
    const git_commit_hash_short = git_commit_hash[0..@min(10, git_commit_hash.len)];

    const exe_options = b.addOptions();

    exe_options.addOption([]const u8, "tag", git_tag);
    exe_options.addOption([]const u8, "commit_hash", git_commit_hash_short);

    exe.root_module.addOptions("build_options", exe_options);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn commandOutput(b: *std.Build, command: []const []const u8, name: []const u8) ![]const u8 {
    var exit_code: u8 = 0;
    const output = b.runAllowFail(command, &exit_code, .Ignore) catch {
        std.debug.print("failed to get {s}, exit code: {d}\n", .{ name, exit_code });
        return error.Exit;
    };
    return std.mem.trim(u8, output, "\r\n");
}
