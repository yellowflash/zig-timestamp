const version = @import("builtin").zig_version;
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run unit tests");

    const zigTimestamp = b.addStaticLibrary(.{ .name = "timestamp", .root_source_file = b.path("timestamp.zig"), .target = target, .optimize = optimize });

    const unit_tests = b.addTest(.{ .root_source_file = b.path("timestamp.zig"), .target = target, .optimize = optimize });

    const module = b.createModule(.{
        .root_source_file = b.path("timestamp.zig"),
    });

    try b.modules.put(b.dupe("timestamp"), module);
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    b.installArtifact(zigTimestamp);
}
