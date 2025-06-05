const std = @import("std");

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var linkage: std.builtin.LinkMode = undefined;

var upstream: std.Build.LazyPath = undefined;

pub fn build(b: *std.Build) void {
    // Get the standard build options.
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});
    linkage = b.option(std.builtin.LinkMode, "linkage", "How to build the library") orelse .static;

    // Get the upstream's file tree.
    upstream = b.dependency("upstream", .{}).path(".");
    if (b.verbose) std.log.info("Upstream Path: {}", .{upstream.dependency.dependency.builder.build_root});

    // Create our targets.
    const core = createCore(b);
    _ = core;

    // -- Extra Steps --

    // Create an unpack step to view the source code we are using.
    const unpack = b.step("unpack", "Installs the unpacked source");
    unpack.dependOn(&b.addInstallDirectory(.{
        .source_dir = upstream,
        .install_dir = .{ .custom = "unpacked" },
        .install_subdir = "",
    }).step);

    // Remove the `zig-out` folder.
    const clean = b.step("clean", "Deletes the `zig-out` folder");
    clean.dependOn(&b.addRemoveDirTree(b.path("zig-out")).step);
}

fn createCore(b: *std.Build) *std.Build.Step.Compile {
    // CMake Target Definition
    //
    // slang_add_target(
    //     .
    //     STATIC
    //     EXPORT_MACRO_PREFIX SLANG
    //     EXCLUDE_FROM_ALL
    //     USE_EXTRA_WARNINGS
    //     LINK_WITH_PRIVATE miniz lz4_static Threads::Threads ${CMAKE_DL_LIBS}
    //     LINK_WITH_PUBLIC unordered_dense::unordered_dense
    //     INCLUDE_DIRECTORIES_PUBLIC
    //         ${slang_SOURCE_DIR}/source
    //         ${slang_SOURCE_DIR}/include
    // )

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    mod.linkLibrary(b.dependency("miniz", .{}).artifact("miniz"));
    mod.linkLibrary(b.dependency("lz4", .{}).artifact("lz4"));
    mod.linkLibrary(b.dependency("unordered_dense", .{}).artifact("unordered_dense"));
    mod.linkLibrary(b.dependency("spirv_headers", .{}).artifact("SPIRV-Headers"));

    const lib = b.addLibrary(.{
        .name = "core",
        .root_module = mod,
        .linkage = linkage,
    });

    lib.addIncludePath(upstream.path(b, "include"));
    lib.addIncludePath(upstream.path(b, "source"));

    lib.installHeadersDirectory(upstream.path("include"), "", .{ .exclude_extensions = &.{".h"} });
    lib.installHeadersDirectory(upstream.path("source"), "", .{ .include_extensions = &.{".h"} });

    lib.addCSourceFiles(.{
        .root = upstream.path("source/core"),
        .files = &.{},
    });

    return lib;
}

// Sources

fn getSources(target: []const u8) []const []const u8 {}
