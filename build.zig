const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The interpreter is a library so the executable and the tests share one copy.
    const mylisp = b.addModule("mylisp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "mylisp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mylisp", .module = mylisp }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the interpreter").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run the unit and end-to-end tests");

    const unit_tests = b.addTest(.{ .root_module = mylisp });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // The script reads .scm files the build graph does not track, so a cached
    // result would go stale when only a test case changes.
    const e2e = b.addSystemCommand(&.{ "sh", "tests/run.sh" });
    e2e.addArtifactArg(exe);
    e2e.has_side_effects = true;
    test_step.dependOn(&e2e.step);

    const fmt = b.addFmt(.{ .paths = &.{ "build.zig", "src" } });
    b.step("fmt", "Format the Zig sources").dependOn(&fmt.step);
}
