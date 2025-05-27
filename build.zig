const std = @import("std");

const Step = std.Build.Step;
const Arg = Step.Run.Arg;

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;
var immutable_upstream: std.Build.LazyPath = undefined;
var upstream: std.Build.LazyPath = undefined;

var lib_core: *Step.Compile = undefined;
var lib_compiler_core: *Step.Compile = undefined;
var lib_prelude: *Step.Compile = undefined;
var lib_slang: *Step.Compile = undefined;

var version: []const u8 = undefined;
var linkage: std.builtin.LinkMode = undefined;

var _install_tools: bool = undefined;
var _debug_build_script: bool = undefined;

// Build

pub fn build(b: *std.Build) void {
    setOptions(b);

    dbg("creating build", .{});

    copyAndPatchUpstream(b) catch @panic("failed to copy upstream");
    addTargets(b) catch @panic("failed to add targets");

    { // unpack step
        const pristine = b.addInstallDirectory(.{
            .install_dir = .{ .custom = "source" },
            .install_subdir = "pristine",
            .source_dir = immutable_upstream,
        });
        const built = b.addInstallDirectory(.{
            .install_dir = .{ .custom = "source" },
            .install_subdir = "built",
            .source_dir = upstream,
        });

        const unpack = b.step("unpack-source", "installs slang's source into zig-out");
        unpack.dependOn(&pristine.step);
        unpack.dependOn(&built.step);

        b.getInstallStep().dependOn(unpack);
    }

    dbg("created build", .{});
}

// Options

// TODO: Define the rest of the options.
fn setOptions(b: *std.Build) void {
    std.log.info("build options", .{});

    target = b.standardTargetOptions(.{});
    std.log.info("\ttarget={}", .{target.result.os.tag});

    optimize = b.standardOptimizeOption(.{});
    std.log.info("\toptimize={}", .{optimize});

    version = b.option([]const u8, "version", "The project version, detected using git if available") orelse getVersion();
    std.log.info("\tversion={s}", .{version});

    linkage = b.option(std.builtin.LinkMode, "linkage", "The link mode for the library.") orelse .static;
    std.log.info("\tlinkage={}", .{linkage});

    // TODO: Remove
    _install_tools = b.option(bool, "_install_tools", "Whether to install the executables of the tools") orelse false;
    std.log.info("\t_install_tools={}", .{_install_tools});

    _debug_build_script = b.option(bool, "_debug_build_script", "Debug printouts for the build script") orelse false;
    std.log.info("\t_debug_build_script={}", .{_debug_build_script});
}

// Upstream

fn copyAndPatchUpstream(b: *std.Build) !void {
    // Copy the upstream to the local zig cache.

    immutable_upstream = b.dependency("slang", .{}).path("");
    const copy_upstream = b.addWriteFiles();

    _ = copy_upstream.addCopyDirectory(immutable_upstream, "", .{});
    upstream = copy_upstream.getDirectory();

    dbg("created step to copy upstream to local cache for editing", .{});

    // Patch the source files to remove out-of-source relative includes.

    const patch_local_upstream = b.addSystemCommand(&.{"bash"});
    patch_local_upstream.addFileArg(b.path("apply_patch"));
    patch_local_upstream.addFileArg(b.path("patch.diff"));
    patch_local_upstream.setCwd(upstream);

    dbg("created patch step to remove out-of-source includes for local copy", .{});

    patch_local_upstream.step.dependOn(&copy_upstream.step);
    b.getInstallStep().dependOn(&patch_local_upstream.step);
}

// Targets

const AddTargetOptions = struct {
    type: enum { library, executable },

    path: []const u8,
    link_with: []const *Step.Compile = &.{},
    external_dependencies: []const enum { lz4, miniz, @"spirv-headers", unordered_dense, lua } = &.{},
    include_directories: []const []const u8 = &.{},
    generated_source_files: []const []const u8 = &.{},

    config_headers: []const []const u8 = &.{},

    file_specific_flags: []const struct {
        file: []const u8,
        flags: []const []const u8,
    } = &.{},
    warnings: enum { extra, fewer, default } = .default,

    linkage: std.builtin.LinkMode = .static,

    pub fn getFlags(self: @This(), allocator: std.mem.Allocator, file_opt: ?[]const u8) []const []const u8 {
        var flags = std.ArrayList([]const u8).init(allocator);
        flags.appendSlice(CompilationFlags.COMMON) catch @panic("OOM");

        switch (self.warnings) {
            .extra => flags.appendSlice(CompilationFlags.EXTRA_WARNINGS) catch @panic("OOM"),
            .fewer => flags.appendSlice(CompilationFlags.FEWER_WARNINGS) catch @panic("OOM"),
            else => {},
        }

        if (file_opt) |file| for (self.file_specific_flags) |fsf| {
            if (std.mem.eql(u8, fsf.file, file)) {
                flags.appendSlice(fsf.flags) catch @panic("OOM");
            }
        };

        return flags.toOwnedSlice() catch @panic("");
    }
};

fn addTarget(b: *std.Build, comptime name: []const u8, options: AddTargetOptions) !*Step.Compile {
    dbg("creating step for compiling target {s} \"{s}\"", .{ if (options.type == .executable) "exe" else "lib", name });

    const root = upstream.path(b, options.path);
    dbg("\troot folder: {s}", .{options.path});

    // Module
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .pic = true,
        .sanitize_c = false,
    });

    // Target
    const compile = switch (options.type) {
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

    // Link With
    for (options.link_with) |link_with| {
        mod.linkLibrary(link_with);
        dbg("\tlinking with \"{s}\"", .{link_with.name});
    }

    // Add C++ Sources
    // TODO: Cache build index
    {
        const allowed_dirs: []const []const u8 = switch (target.result.os.tag) {
            .windows => &[_][]const u8{ "", "windows" },
            .linux => &[_][]const u8{ "", "unix" },
            else => &[_][]const u8{""},
        };

        const dir = try immutable_upstream.path(b, options.path).getPath3(b, null).openDir(".", .{ .iterate = true });
        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        const _dbg_link_objects = mod.link_objects.items.len;
        dbg("\tsearching {s} for .cpp files", .{try dir.realpathAlloc(b.allocator, ".")});

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

            mod.addCSourceFile(.{ .file = root.path(b, entry.path), .flags = options.getFlags(b.allocator, entry.path) });
        }

        dbg("\tfound {} .cpp files", .{mod.link_objects.items.len - _dbg_link_objects});

        mod.addCSourceFiles(.{
            .files = options.generated_source_files,
            .root = root,
            .flags = options.getFlags(b.allocator, null),
        });
    }

    // Include Directories
    mod.addIncludePath(root);
    dbg("\tnew include path: {s}", .{options.path});
    for (options.include_directories) |dir| {
        mod.addIncludePath(upstream.path(b, dir));
        dbg("\tnew include path: {s}", .{dir});
    }

    // Compiler Definitions
    try mod.c_macros.append(b.allocator, "-DSLANG_ENABLE_DXIL_SUPPORT=1");
    try mod.c_macros.append(b.allocator, "-DSLANG_ENABLE_IR_BREAK_ALLOC");
    try mod.c_macros.append(b.allocator, "-DSLANG_USE_SYSTEM_SPIRV_HEADER");

    if (optimize == .Debug) try mod.c_macros.append(b.allocator, "-D_DEBUG");
    try mod.c_macros.append(b.allocator, "-DNOMINMAX");
    try mod.c_macros.append(b.allocator, "-DWIN32_LEAN_AND_MEAN");
    try mod.c_macros.append(b.allocator, "-DVC_EXTRALEAN");
    try mod.c_macros.append(b.allocator, "-DUNICODE");
    try mod.c_macros.append(b.allocator, "-D_UNICODE");
    switch (options.linkage) {
        .dynamic => {
            try mod.c_macros.append(b.allocator, "-DSLANG_DYNAMIC");
            try mod.c_macros.append(b.allocator, "-DSLANG_DYNAMIC_EXPORT");
        },
        .static => {
            try mod.c_macros.append(b.allocator, "-DSLANG_STATIC");
            try mod.c_macros.append(b.allocator, "-DSTB_IMAGE_STATIC");
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

    // Config Headers
    for (options.config_headers) |config_header| {
        const conf = b.addConfigHeader(.{
            .style = .{ .cmake = immutable_upstream.path(b, config_header) },
        }, .{
            .SLANG_VERSION_FULL = version,
        });

        mod.addIncludePath(conf.getOutput().dirname());
        compile.step.dependOn(&conf.step);

        dbg("\tconfig header: {s}", .{config_header});
    }

    return compile;
}

fn addTargets(b: *std.Build) !void {
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

    lib_prelude = try addTarget(b, "prelude", .{
        .type = .library,
        .path = "prelude",
        .external_dependencies = &.{.unordered_dense},
        .include_directories = &.{"include"},
        .generated_source_files = &.{
            "slang-cpp-host-prelude.h.cpp",
            "slang-cpp-prelude.h.cpp",
            "slang-cuda-prelude.h.cpp",
            "slang-hlsl-prelude.h.cpp",
            "slang-torch-prelude.h.cpp",
        },
        .linkage = linkage,
    });
    lib_prelude.step.dependOn(try runSlangEmbed(b));
    b.installArtifact(lib_prelude);

    lib_slang = try addTarget(b, "slang", .{
        .type = .library,
        .path = "source/slang",
        .link_with = &.{ lib_core, lib_compiler_core, lib_prelude },
        .external_dependencies = &.{ .miniz, .unordered_dense, .lz4, .@"spirv-headers" },
        .include_directories = &.{ "source", "include", "source/slang/capability", "source/slang/fiddle" },
        .config_headers = &.{"slang-tag-version.h.in"},
        .linkage = linkage,
    });
    lib_slang.step.dependOn(try runSlangFiddle(b));
    lib_slang.step.dependOn(try runSlangCapabilityGenerator(b));
    lib_slang.step.dependOn(try runSlangLookupGenerator(b));
    lib_slang.step.dependOn(try runSlangSpirvEmbedGenerator(b));
    b.installArtifact(lib_slang);
}

// Tools

const RunToolOptions = struct {
    add_target_options: AddTargetOptions,
    cwd: std.Build.LazyPath,
    run_arguments: []const Run,

    pub const Run = struct {
        system_command_before: ?[]const Arg = null,
        run: []const Arg,
        system_command_after: ?[]const Arg = null,
    };
};

fn runTool(b: *std.Build, comptime name: []const u8, options: RunToolOptions) !*Step {
    dbg("\tdepending on tool: {s}", .{name}); // Assumes call right after the target was created.

    const exe = try addTarget(b, name, options.add_target_options);
    if (_install_tools) b.installArtifact(exe);

    var run = b.step("run-" ++ name, "");
    run.* = Step.init(.{
        .name = "run-" ++ name,
        .id = .custom,
        .owner = b,
    });

    // TODO: Ahhhhhh, decouple tool exe and run
    for (options.run_arguments) |run_set| {
        const step = b.addRunArtifact(exe);
        step.cwd = options.cwd;

        try step.argv.appendSlice(b.allocator, run_set.run);

        if (_debug_build_script) {
            const echo = b.addSystemCommand(&.{ "echo", "[build] running tool in" });
            echo.addFileArg(options.cwd);
            echo.addArg("\n\t");
            echo.addArg(name);
            if (run_set.run.len > 20) {
                try echo.argv.appendSlice(b.allocator, run_set.run[0..20]);
                echo.addArg("...");
            } else {
                try echo.argv.appendSlice(b.allocator, run_set.run);
            }
            step.step.dependOn(&echo.step);
        }

        if (run_set.system_command_before) |argv| {
            const run_step = Step.Run.create(b, "before");
            run_step.setCwd(options.cwd);
            try run_step.argv.appendSlice(b.allocator, argv);
            step.step.dependOn(&run_step.step);
        }

        const after = if (run_set.system_command_before) |argv| b: {
            const run_step = Step.Run.create(b, "after");
            run_step.setCwd(options.cwd);
            try run_step.argv.appendSlice(b.allocator, argv);
            run_step.step.dependOn(&step.step);
            break :b &step.step;
        } else &step.step;

        run.dependOn(after);
    }

    return run;
}

fn runSlangCapabilityGenerator(b: *std.Build) !*Step {
    return runTool(
        b,
        "slang-capability-generator",
        .{
            .add_target_options = .{
                .type = .executable,
                .path = "tools/slang-capability-generator",
                .include_directories = &.{"include"},
                .link_with = &.{lib_compiler_core},
                .external_dependencies = &.{.unordered_dense},
                .linkage = .dynamic,
            },
            .cwd = upstream,
            .run_arguments = &.{.{
                .system_command_before = strArgs(b, &.{ "mkdir", "-p", "source/slang/capability" }),
                .run = strArgs(b, &.{
                    "source/slang/slang-capabilities.capdef",
                    "--target-directory",
                    "source/slang/capability",
                    "--doc",
                    "docs/user-guide/a3-02-reference-capability-atoms.md",
                }),
            }},
        },
    );
}

fn runSlangEmbed(b: *std.Build) !*Step {
    return runTool(b, "slang-embed", .{
        .add_target_options = .{
            .type = .executable,
            .path = "tools/slang-embed",
            .include_directories = &.{"include"},
            .link_with = &.{lib_core},
            .external_dependencies = &.{.unordered_dense},
            .linkage = .dynamic,
        },
        .cwd = upstream.path(b, "prelude"),
        .run_arguments = &.{
            .{ .run = strArgs(b, &.{ "slang-cpp-host-prelude.h", "slang-cpp-host-prelude.h.cpp" }) },
            .{ .run = strArgs(b, &.{ "slang-cpp-prelude.h", "slang-cpp-prelude.h.cpp" }) },
            .{ .run = strArgs(b, &.{ "slang-cuda-prelude.h", "slang-cuda-prelude.h.cpp" }) },
            .{ .run = strArgs(b, &.{ "slang-hlsl-prelude.h", "slang-hlsl-prelude.h.cpp" }) },
            .{ .run = strArgs(b, &.{ "slang-torch-prelude.h", "slang-torch-prelude.h.cpp" }) },
        },
    });
}

fn runSlangFiddle(b: *std.Build) !*Step {
    return runTool(b, "slang-fiddle", .{
        .add_target_options = .{
            .type = .executable,
            .path = "tools/slang-fiddle",
            .include_directories = &.{ "source", "include" },
            .link_with = &.{lib_compiler_core},
            .external_dependencies = &.{ .unordered_dense, .lua },
            .linkage = .dynamic,
        },
        .cwd = upstream,
        .run_arguments = &.{
            .{
                .system_command_before = strArgs(b, &.{ "mkdir", "-p", "source/slang/fiddle" }),
                .run = a: {
                    var args = std.ArrayList([]const u8).init(b.allocator);
                    args.appendSlice(&.{ "-i", "source/slang/", "-o", "source/slang/fiddle/" }) catch @panic("OOM");
                    const dir = immutable_upstream.getPath3(b, null).openDir("source/slang", .{ .iterate = true }) catch @panic("dir");
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        if (entry.kind != .file or !(std.mem.endsWith(u8, entry.name, ".cpp") or std.mem.endsWith(u8, entry.name, ".h"))) continue;
                        args.append(b.dupe(entry.name)) catch @panic("OOM");
                    }
                    break :a strArgs(b, args.toOwnedSlice() catch @panic("OOM"));
                },
            },
        },
    });
}

fn runSlangLookupGenerator(b: *std.Build) !*Step {
    return runTool(b, "slang-lookup-generator", .{
        .add_target_options = .{
            .type = .executable,
            .path = "tools/slang-lookup-generator",
            .include_directories = &.{"include"},
            .link_with = &.{lib_compiler_core},
            .external_dependencies = &.{.unordered_dense},
            .linkage = .dynamic,
        },
        .cwd = upstream,
        .run_arguments = &.{.{
            .system_command_before = strArgs(b, &.{ "mkdir", "-p", "source/slang/slang-lookup-tables" }),
            .run = &.{
                pathArg(b.dependency("spirv-headers", .{}).path("include/spirv/unified1/extinst.glsl.std.450.grammar.json")),
                strArg(b, "source/slang/slang-lookup-tables/slang-lookup-GLSLstd450.cpp"),
                strArg(b, "GLSLstd450"),
                strArg(b, "GLSLstd450"),
                pathArg(b.dependency("spirv-headers", .{}).path("include/spirv/unified1/GLSL.std.450.h")),
            },
        }},
    });
}

fn runSlangSpirvEmbedGenerator(b: *std.Build) !*Step {
    return runTool(b, "slang-spirv-embed-generator", .{
        .add_target_options = .{
            .type = .executable,
            .path = "tools/slang-spirv-embed-generator",
            .include_directories = &.{"include"},
            .link_with = &.{lib_compiler_core},
            .external_dependencies = &.{ .unordered_dense, .@"spirv-headers" },
            .linkage = .dynamic,
        },
        .cwd = upstream,
        .run_arguments = &.{.{
            .system_command_before = strArgs(b, &.{ "mkdir", "-p", "source/slang/slang-lookup-tables" }),
            .run = &.{
                pathArg(b.dependency("spirv-headers", .{}).path("include/spirv/unified1/spirv.core.grammar.json")),
                strArg(b, "source/slang/slang-lookup-tables/slang-spirv-core-grammar-embed.cpp"),
            },
        }},
    });
}

// External Dependencies

fn miniz(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("miniz", .{});

    mod.addIncludePath(dep.path(""));
    mod.addCSourceFile(.{ .file = dep.path("miniz.c") });

    dbg("\tlinking with miniz", .{});
}

fn unordered_dense(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("unordered_dense", .{});

    mod.addIncludePath(dep.path("include"));

    dbg("\tlinking with unordered_dense", .{});
}

fn spriv_headers(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("spirv-headers", .{});

    mod.addIncludePath(dep.path("include"));

    dbg("\tlinking with spirv_headers", .{});
}

fn lz4(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    });

    mod.linkLibrary(dep.artifact("lz4"));

    dbg("\tlinking with lz4", .{});
}

fn lua(b: *std.Build, mod: *std.Build.Module) void {
    const dep = b.dependency("lua", .{
        .target = target,
        .release = optimize != .Debug,
    });

    mod.linkLibrary(dep.artifact(if (target.result.os.tag == .windows) "lua54" else "lua"));

    dbg("\tlinking with lua", .{});
}

// Version

fn getVersion() []const u8 {
    const @"build.zig.zon" = @embedFile("build.zig.zon");
    var lines = std.mem.splitScalar(u8, @"build.zig.zon", '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), ".version")) {
        var iter = std.mem.tokenizeScalar(u8, line, ' ');
        _ = iter.next();
        _ = iter.next();

        return std.mem.trim(u8, iter.next().?, "\",");
    };
    @panic("no .version in build.zig.zon!");
}

// Misc.

fn strArg(b: *std.Build, str: []const u8) Arg {
    return Arg{ .bytes = b.dupe(str) };
}

fn strArgs(b: *std.Build, strs: []const []const u8) []const Arg {
    var args = std.ArrayList(Arg).initCapacity(b.allocator, strs.len) catch @panic("OOM");
    for (strs) |str| args.appendAssumeCapacity(strArg(b, str));
    return args.toOwnedSlice() catch @panic("");
}

fn pathArg(path: std.Build.LazyPath) Arg {
    return Arg{ .lazy_path = .{ .lazy_path = path, .prefix = "" } };
}

fn dbg(comptime msg: []const u8, args: anytype) void {
    if (_debug_build_script) std.debug.print("[debug] " ++ msg ++ "\n", args);
}

// Compilation Flags

const CompilationFlags = struct {
    pub const COMMON = &.{
        // C++ Standard
        "-std=gnu++20",
        // Warnings
        "-Wall",
        "-Wno-switch",
        "-Wno-parentheses",
        "-Wno-unused-local-typedefs",
        // "-Wno-class-memaccess",
        "-Wno-assume",
        "-Wno-reorder",
        "-Wno-invalid-offsetof",
        "-Wno-newline-eof",
        "-Wno-return-std-move",
        "-Werror=return-local-addr",
        "-Wnarrowing",
        // Flags
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden",
        // Not spec
        "-Wno-unused-function",
        "-Wno-unused-value",
        "-Wno-unused-but-set-variable",
    };
    pub const EXTRA_WARNINGS = &.{
        "-Wextra",
    };
    pub const FEWER_WARNINGS = &.{
        "-Wno-class-memaccess",
        "-Wno-unused-variable",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-Wno-unused-function",
        "-Wno-unused-value",
        "-Wno-unused-but-set-variable",
        "-Wno-implicit-fallthrough",
        "-Wno-missing-field-initializers",
        "-Wno-strict-aliasing",
        "-Wno-maybe-uninitialized",
    };
};
