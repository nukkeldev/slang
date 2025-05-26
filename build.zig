const std = @import("std");

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var immutable_upstream: std.Build.LazyPath = undefined;
var upstream: std.Build.LazyPath = undefined;

var lib_core: *std.Build.Step.Compile = undefined;
var lib_compiler_core: *std.Build.Step.Compile = undefined;

// Build

pub fn build(b: *std.Build) !void {
    // Copy upstream to local cache.
    try configure_upstream(b);

    // Options
    target = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode for the library.") orelse .static;
    // TODO: Define the rest of the options.

    // Libraries
    lib_core = try addTarget(b, "core", .{
        .type = .library,
        .path = "source/core",
        .external_dependencies = &.{ .miniz, .unordered_dense, .lz4 },
        .include_directories = &.{ "source", "include" },
        .linkage = linkage,
    });
    b.installArtifact(lib_core);

    lib_compiler_core = try addTarget(b, "compiler-core", .{
        .type = .library,
        .path = "source/compiler-core",
        .link_with = &.{lib_core}, // TODO: Propigate
        .external_dependencies = &.{ .@"spirv-headers", .unordered_dense },
        .include_directories = &.{ "source", "include" },
        .file_specific_flags = &.{.{ .file = "slang-dxc-compiler.cpp", .flags = &.{"-fms-extensions"} }},
        .linkage = linkage,
    });
    b.installArtifact(lib_compiler_core);

    const prelude = try addTarget(b, "prelude", .{
        .type = .library,
        .path = "prelude",
        .external_dependencies = &.{.unordered_dense},
        .include_directories = &.{"include"},
        .linkage = linkage,
    });
    prelude.step.dependOn(try embed_prelude(b));
    b.installArtifact(prelude);

    _ = try fiddle(b);
}

// Targets

const TargetOptions = struct {
    type: enum { library, executable },

    path: []const u8,
    link_with: []const *std.Build.Step.Compile = &.{},
    external_dependencies: []const enum { lz4, miniz, @"spirv-headers", unordered_dense, lua } = &.{},
    include_directories: []const []const u8 = &.{},

    file_specific_flags: []const struct {
        file: []const u8,
        flags: []const []const u8,
    } = &.{},

    linkage: std.builtin.LinkMode = .static,
};

fn addTarget(b: *std.Build, name: []const u8, options: TargetOptions) !*std.Build.Step.Compile {
    const root = upstream.path(b, options.path);

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

        const allowed_dirs: []const []const u8 = switch (target.result.os.tag) {
            .windows => &[_][]const u8{ "", "windows" },
            .linux => &[_][]const u8{ "", "unix" },
            else => &[_][]const u8{""},
        };

        const dir = try immutable_upstream.path(b, options.path).getPath3(b, null).openDir(".", .{ .iterate = true });
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
    for (options.include_directories) |dir| mod.addIncludePath(upstream.path(b, dir));

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
        .lua => lua(b, mod),
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

// Upstream

fn configure_upstream(b: *std.Build) !void {
    // Copy the upstream to the local zig cache.

    immutable_upstream = b.dependency("slang", .{}).path("");
    const copy_upstream = b.addWriteFiles();

    _ = copy_upstream.addCopyDirectory(immutable_upstream, "", .{});

    upstream = copy_upstream.getDirectory();

    // Patch the source files to remove out-of-source relative includes.

    const patch_local_upstream = b.addSystemCommand(&.{"bash"});
    patch_local_upstream.addFileArg(b.path("apply_patch"));
    patch_local_upstream.addFileArg(b.path("patch.diff"));
    patch_local_upstream.setCwd(upstream);

    patch_local_upstream.step.dependOn(&copy_upstream.step);

    b.getInstallStep().dependOn(&patch_local_upstream.step);
}

// Tools

fn generate_capabilities(b: *std.Build) !*std.Build.Step {
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

    return run_capability_generator;
}

fn embed_prelude(b: *std.Build) !*std.Build.Step {
    const exe_embed = try addTarget(b, "slang-embed", .{
        .type = .executable,
        .path = "tools/slang-embed",
        .include_directories = &.{"include"},
        .link_with = &.{lib_core},
        .external_dependencies = &.{.unordered_dense},
        .linkage = .dynamic,
    });
    b.installArtifact(exe_embed);

    var run_embed = try b.allocator.create(std.Build.Step);
    run_embed.* = std.Build.Step.init(.{
        .name = "run-embed",
        .id = .custom,
        .owner = b,
    });

    const files = &.{
        "slang-cpp-host-prelude.h",
        "slang-cpp-prelude.h",
        "slang-cuda-prelude.h",
        "slang-hlsl-prelude.h",
        "slang-torch-prelude.h",
    };

    inline for (files) |file| {
        const run = b.addRunArtifact(exe_embed);
        run.cwd = upstream.path(b, "prelude");
        run.addArgs(&.{ file, file ++ ".cpp" });
        run_embed.dependOn(&run.step);
    }

    return run_embed;
}

fn fiddle(b: *std.Build) !*std.Build.Step {
    const exe_fiddle = try addTarget(b, "slang-fiddle", .{
        .type = .executable,
        .path = "tools/slang-fiddle",
        .include_directories = &.{ "source", "include" },
        .link_with = &.{lib_compiler_core},
        .external_dependencies = &.{ .unordered_dense, .lua },
        .linkage = .dynamic,
    });
    b.installArtifact(exe_fiddle);

    return &exe_fiddle.step;
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

fn lua(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("lua", .{
        .target = target,
        .release = optimize != .Debug,
    });

    mod.linkLibrary(dep.artifact(if (target.result.os.tag == .windows) "lua54" else "lua"));
}
