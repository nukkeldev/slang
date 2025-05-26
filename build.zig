const std = @import("std");
const builtin = @import("builtin");

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var upstream: *std.Build.Dependency = undefined;

// Build

pub fn build(b: *std.Build) !void {
    // Upstream
    upstream = b.dependency("slang", .{});

    // Options
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode for the library.") orelse .static;
    // TODO: Define the rest of the options.

    // Libraries
    const lib_core = try addTarget(b, "core", .{
        .type = .library,
        .path = "source/core",
        .external_dependencies = &.{ .miniz, .unordered_dense, .lz4 },
        .include_directories = &.{ "source", "include" },
        .linkage = linkage,
    });
    b.installArtifact(lib_core);

    const lib_compiler_core = try addTarget(b, "compiler-core", .{
        .type = .library,
        .path = "source/compiler-core",
        .link_with = &.{lib_core}, // TODO: Propigate
        .external_dependencies = &.{ .@"spirv-headers", .unordered_dense },
        .include_directories = &.{ "source", "include" },
        .file_specific_flags = &.{.{ .file = "slang-dxc-compiler.cpp", .flags = &.{"-fms-extensions"} }},
        .linkage = linkage,
    });
    b.installArtifact(lib_compiler_core);

    // const prelude = try addTarget(b, mod, "prelude", .{
    //     .type = .library,
    //     .path = "prelude",
    //     .include_directories = &.{ "source", "include" },
    // });

    // Tools
    // -- slang-capability-generator
    const exe_capability_generator = try addTarget(b, "slang-capability-generator", .{
        .type = .executable,
        .path = "tools/slang-capability-generator",
        .include_directories = &.{"include"},
        .link_with = &.{lib_compiler_core},
        .external_dependencies = &.{.unordered_dense},
        .linkage = .dynamic,
    });
    b.installArtifact(exe_capability_generator);

    const run_capability_generator = b.addRunArtifact(exe_capability_generator);
    run_capability_generator.cwd = upstream.path("");
    run_capability_generator.addArgs(&.{
        "source/slang/slang-capabilities.capdef",
        "--target-directory",
        "source/slang/capability",
        "--doc",
        "docs/user-guide/a3-02-reference-capability-atoms.md",
    });
    // -- slang-embed
    const exe_embed = try addTarget(b, "slang-embed", .{
        .type = .executable,
        .path = "tools/slang-embed",
        .include_directories = &.{"include"},
        .link_with = &.{lib_core},
        .external_dependencies = &.{.unordered_dense},
        .linkage = .dynamic,
    });
    b.installArtifact(exe_embed);

    const run_embed = b.addRunArtifact(exe_capability_generator);
    run_embed.cwd = upstream.path("");
    run_embed.addArgs(&.{
        "source/slang/slang-capabilities.capdef",
        "--target-directory",
        "source/slang/capability",
        "--doc",
        "docs/user-guide/a3-02-reference-capability-atoms.md",
    });
}

// Targets

const TargetOptions = struct {
    type: enum { library, executable },

    path: []const u8,
    link_with: []const *std.Build.Step.Compile = &.{},
    external_dependencies: []const enum { lz4, miniz, @"spirv-headers", unordered_dense } = &.{},
    include_directories: []const []const u8 = &.{},

    file_specific_flags: []const struct {
        file: []const u8,
        flags: []const []const u8,
    } = &.{},

    linkage: std.builtin.LinkMode = .static,
};

fn addTarget(b: *std.Build, name: []const u8, options: TargetOptions) !*std.Build.Step.Compile {
    const root = upstream.path(options.path);

    // Module
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .pic = true,
    });

    // Link With
    for (options.link_with) |link_with| mod.linkLibrary(link_with);

    // Add C++ Sources
    {
        var file_specific_flags = std.StringHashMap([]const []const u8).init(b.allocator);
        for (options.file_specific_flags) |fsf| {
            try file_specific_flags.put(fsf.file, fsf.flags);
        }
        defer file_specific_flags.deinit();

        const allowed_dirs: []const []const u8 = &[_][]const u8{""} ++ switch (builtin.os.tag) {
            .windows => &[_][]const u8{"windows"},
            .linux => &[_][]const u8{"unix"},
            else => &[_][]const u8{},
        };

        const dir = try upstream.path(options.path).getPath3(b, null).openDir(".", .{ .iterate = true });
        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".cpp")) continue;

            if (std.fs.path.dirname(entry.path)) |dirname| {
                var allowed = false;
                for (allowed_dirs) |allowed_dir| if (std.mem.eql(u8, allowed_dir, dirname)) {
                    allowed = true;
                    break;
                };
                if (!allowed) continue;
            }

            mod.addCSourceFile(.{
                .file = root.path(b, entry.path),
                .flags = file_specific_flags.get(entry.path) orelse &.{},
            });
        }
    }

    // Include Directories
    mod.addIncludePath(root);
    for (options.include_directories) |dir| mod.addIncludePath(upstream.path(dir));

    // Compiler Definitions
    switch (options.linkage) {
        .dynamic => {
            mod.addCMacro("SLANG_DYNAMIC", "");
            mod.addCMacro("SLANG_DYNAMIC_EXPORT", "");
        },
        .static => {
            mod.addCMacro("SLANG_STATIC", "");
        },
    }

    // External Dependencies
    for (options.external_dependencies) |dep| switch (dep) {
        .miniz => miniz(b, mod),
        .unordered_dense => unordered_dense(b, mod),
        .@"spirv-headers" => spriv_headers(b, mod),
        .lz4 => lz4(b, mod),
    };

    // TODO: installHeadersDirectory?

    return switch (options.type) {
        .library => b.addLibrary(.{
            .name = name,
            .root_module = mod,
            .linkage = options.linkage,
        }),
        .executable => b.addExecutable(.{
            .name = name,
            .root_module = mod,
            .linkage = options.linkage,
        }),
    };
}

// External Dependencies

fn miniz(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("miniz", .{});

    mod.addIncludePath(dep.path(""));
    mod.addCSourceFile(.{ .file = dep.path("miniz.c") });
}

fn unordered_dense(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("unordered_dense", .{});

    mod.addIncludePath(dep.path("include"));
}

fn spriv_headers(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("spirv-headers", .{});

    mod.addIncludePath(dep.path("include"));
}

fn lz4(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    });

    mod.linkLibrary(dep.artifact("lz4"));
}
