const std = @import("std");

pub fn build(b: *std.Build) void {
    // Get the upstream's file tree.
    const upstream = b.dependency("upstream", .{}).path(".");
    if (b.verbose) std.log.info("Upstream Path: {}", .{upstream.dependency.dependency.builder.build_root});

    // -- Extra Steps --

    // Create an unpack step to view the source code we are using.
    const unpack = b.step("unpack", "Installs the unpacked source");
    unpack.dependOn(&b.addInstallDirectory(.{
        .source_dir = upstream,
        .install_dir = .{ .custom = "unpacked" },
        .install_subdir = "",
    }).step);
}
