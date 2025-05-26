const std = @import("std");

var upstream: *std.Build.Dependency = undefined;

const TargetOptions = struct {
    path: []const u8,
    include_directories: []const []const u8,

    file_specific_flags: []const struct {
        file: []const u8,
        flags: []const []const u8,
    } = &.{},

    linkage: std.builtin.LinkMode = .static,
};

fn addTarget(b: *std.Build, mod: *std.Build.Module, name: []const u8, options: TargetOptions) !*std.Build.Step.Compile {
    const root = upstream.path(options.path);

    // Library
    const lib = b.addLibrary(.{
        .name = name,
        .root_module = mod,
        .linkage = options.linkage,
    });

    // Add C++ Sources
    {
        var file_specific_flags = std.StringHashMap([]const []const u8).init(b.allocator);
        for (options.file_specific_flags) |fsf| {
            try file_specific_flags.put(fsf.file, fsf.flags);
        }
        defer file_specific_flags.deinit();

        const dir = try upstream.path(options.path).getPath3(b, null).openDir(".", .{ .iterate = true });
        var iter = dir.iterate();

        while (try iter.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".cpp")) continue;
            lib.addCSourceFile(.{
                .file = root.path(b, entry.name),
                .flags = file_specific_flags.get(entry.name) orelse &.{},
            });
        }

        // TODO: Add platform-specific dependencies for i.e. `windows/` sub-folder.
    }

    // Include Directories
    lib.addIncludePath(root);
    for (options.include_directories) |dir| lib.addIncludePath(upstream.path(dir));

    // TODO: installHeadersDirectory?

    return lib;
}

pub fn build(b: *std.Build) !void {
    // Upstream
    upstream = b.dependency("slang", .{});

    // Options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode for the library.") orelse .static;
    // TODO: Define the rest of the options.

    // External Dependencies
    // -- Raw
    const miniz = b.dependency("miniz", .{});
    const unordered_dense = b.dependency("unordered_dense", .{});
    const spriv_headers = b.dependency("spirv-headers", .{});

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

    // External Dependency Installation
    // -- miniz
    mod_slang.addIncludePath(miniz.path(""));
    mod_slang.addCSourceFile(.{ .file = miniz.path("miniz.c") });
    // -- ankerl/unordered_dense
    mod_slang.addIncludePath(unordered_dense.path("include"));
    // -- spirv-headers
    mod_slang.addIncludePath(spriv_headers.path("include"));
    // -- lz4
    mod_slang.linkLibrary(lz4.artifact("lz4"));

    // Compiler Definitions
    switch (linkage) {
        .dynamic => {
            mod_slang.addCMacro("SLANG_DYNAMIC", "");
            mod_slang.addCMacro("SLANG_DYNAMIC_EXPORT", "");
        },
        .static => {
            mod_slang.addCMacro("SLANG_STATIC", "");
        },
    }

    // Libraries
    // const lib = b.addLibrary(.{
    //     .name = "slang",
    //     .root_module = mod_slang,
    //     .linkage = linkage,
    // });
    // b.installArtifact(lib);

    const lib_core = try addTarget(b, mod_slang, "core", .{
        .path = "source/core",
        .include_directories = &.{ "source", "include" },
        .linkage = linkage,
    });
    b.installArtifact(lib_core);

    const lib_compiler_core = try addTarget(b, mod_slang, "compiler-core", .{
        .path = "source/compiler-core",
        .include_directories = &.{ "source", "include" },
        .file_specific_flags = &.{.{ .file = "slang-dxc-compiler.cpp", .flags = &.{"-fms-extensions"} }},
        .linkage = linkage,
    });
    b.installArtifact(lib_compiler_core);
}
