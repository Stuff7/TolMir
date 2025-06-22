const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addBuild(b, target, optimize);
    b.installArtifact(exe);

    const check = addBuild(b, target, optimize);
    const check_step = b.step("check", "Build for LSP Diagnostics");
    check_step.dependOn(&check.step);
}

fn addBuild(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const suffix = switch (optimize) {
        .Debug => "-dbg",
        .ReleaseFast => "",
        .ReleaseSafe => "-s",
        .ReleaseSmall => "-sm",
    };

    const NAME = "tolmir";
    var name_buf: [NAME.len + 4]u8 = undefined;
    const exe = b.addExecutable(.{
        .name = std.fmt.bufPrint(@constCast(&name_buf), "{s}{s}", .{ NAME, suffix }) catch unreachable,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addIncludePath(.{ .cwd_relative = "vendor/libarchive/libarchive" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "vendor/libb2/src" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "vendor/zlib" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "vendor/mxml" });
    exe.root_module.addIncludePath(.{ .cwd_relative = "vendor/xz/src/liblzma/lzma" });

    exe.addObjectFile(.{ .cwd_relative = "vendor/libarchive/build/libarchive/libarchive.a" });
    exe.addObjectFile(.{ .cwd_relative = "vendor/libb2/build/src/.libs/libb2.a" });
    exe.addObjectFile(.{ .cwd_relative = "vendor/zlib/build.included/libz.a" });
    exe.addObjectFile(.{ .cwd_relative = "vendor/xz/src/liblzma/.libs/liblzma.a" });
    exe.addObjectFile(.{ .cwd_relative = "vendor/mxml/libmxml4.a" });
    exe.linkLibC();

    return exe;
}
