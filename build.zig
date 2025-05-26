const std = @import("std");

// TODO: zig fetch does not support submodules so we need to provide our own linking to dependencies.

pub fn build(b: *std.Build) !void {
    // Upstream
    const upstream = b.dependency("slang", .{});

    // Options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode for the library.") orelse .static;
    // TODO: Define the rest of the options.

    // External Dependencies
    // -- Raw
    const miniz = b.dependency("miniz", .{});
    const unordered_dense = b.dependency("unordered_dense", .{});

    // -- Wrapped
    const lz4 = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    });

    // Module
    const mod_slang = b.addModule("slang", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
        // .sanitize_c = null, // ?
    });

    // Add external dependencies to module.
    // -- miniz
    mod_slang.addIncludePath(miniz.path(""));
    mod_slang.addCSourceFile(.{ .file = miniz.path("miniz.c") });
    // -- ankerl/unordered_dense
    mod_slang.addIncludePath(unordered_dense.path("include"));
    // -- lz4
    mod_slang.linkLibrary(lz4.artifact("lz4"));

    // Library
    const lib_slang = b.addLibrary(.{
        .name = "slang",
        .root_module = mod_slang,
        .linkage = linkage,
    });
    b.installArtifact(lib_slang);

    // slang/core

    const lib_slang_core = b.addLibrary(.{
        .name = "core",
        .root_module = mod_slang,
        .linkage = .static,
    });

    // Open the source directory and collect all .cpp files' relative paths.
    const lib_slang_core_sources = b: {
        var sources = std.ArrayList([]const u8).init(b.allocator);

        const dir = try upstream.path("source/core").getPath3(b, null).openDir(".", .{ .iterate = true });
        var iter = dir.iterate();

        while (try iter.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".cpp")) continue;
            try sources.append(try b.allocator.dupe(u8, entry.name));
        }

        break :b try sources.toOwnedSlice();
    };

    // Add the sources to our library.
    lib_slang_core.addCSourceFiles(.{
        .root = upstream.path("source/core"),
        .files = lib_slang_core_sources,
    });

    // Set the include paths.
    lib_slang_core.addIncludePath(upstream.path("source"));
    lib_slang_core.addIncludePath(upstream.path("include"));
    lib_slang_core.addIncludePath(upstream.path("source/core"));

    // Add our external dependencies.

    // TODO: installHeadersDirectory?
}
