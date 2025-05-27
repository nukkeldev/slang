const std = @import("std");

// Standard Build Options

var target: std.Build.ResolvedTarget = undefined;
var optimize: std.builtin.OptimizeMode = undefined;

// Slang Build Options

// Taken from https://github.com/shader-slang/slang/blob/master/docs/building.md#cmake-options.

/// The project version, if not specified, from build.zig.zon
var slang_version: []const u8 = getVersion();
/// TODO: Build slang with an embedded version of the core module
var slang_embed_core_module: bool = true;
/// TODO: Embed the core module source in the binary
var slang_embed_core_module_source: bool = true;
/// TODO: Enable generating DXIL using DXC
var slang_enable_dxil: bool = true;
/// TODO: Enable ASAN (address sanitizer)
var slang_enable_asan: bool = false;
/// TODO: Enable full IR validation (SLOW!)
var slang_enable_full_ir_validation: bool = false;
/// TODO: Enable IR BreakAlloc functionality for debugging
var slang_enable_ir_break_alloc: bool = false;
/// TODO: Enable gfx targets
var slang_enable_gfx: bool = true;
/// TODO: Enable language server target
var slang_enable_slangd: bool = true;
/// TODO: Enable standalone compiler target
var slang_enable_slangc: bool = true;
/// TODO: Enable Slang interpreter target
var slang_enable_slangi: bool = true;
/// TODO: Enable runtime target
var slang_enable_slangrt: bool = true;
/// TODO: Enable glslang dependency and slang-glslang wrapper target
var slang_enable_slang_glslang: bool = true;
/// TODO: Enable test targets, requires SLANG_ENABLE_GFX, SLANG_ENABLE_SLANGD and SLANG_ENABLE_SLANGRT
var slang_enable_tests: bool = true;
/// TODO: Enable example targets, requires SLANG_ENABLE_GFX
var slang_enable_examples: bool = true;
/// TODO: How to build the slang library
/// NOTE: This was changed from the original .dynamic default.
var slang_lib_type: std.builtin.LinkMode = .static;
/// TODO: Enable generating debug info for Release configs
var slang_enable_release_debug_info: bool = true;
/// TODO: Enable LTO for Release builds
var slang_enable_release_lto: bool = true;
/// TODO: Enable generating split debug info for Debug and RelWithDebInfo configs
var slang_enable_split_debug_info: bool = true;
/// TODO: How to set up llvm support
var slang_slang_llvm_flavor: []const u8 = "FETCH_BINARY_IF_POSSIBLE";
/// TODO: URL specifying the location of the slang-llvm prebuilt library
var slang_slang_llvm_binary_url: []const u8 = undefined; // TODO: Depends on target system.
/// TODO: Path to an installed generator target binaries for cross compilation
var slang_generators_path: ?[]const u8 = null; // TODO: Remove this.

// The following options relate to optional dependencies for additional backends and running additional tests.
// Left unchanged they are auto detected, however they can be set to OFF to prevent their usage, or set to ON
// to make it an error if they can't be found.

/// TODO: Enable running tests with the CUDA backend, doesn't affect the targets Slang itself supports
var slang_enable_cuda: ?bool = null;
var cudatoolkit_root: ?[]const u8 = null;
var cuda_path: ?[]const u8 = null;
/// TODO: Requires CUDA
var slang_enable_optix: ?bool = null;
var optix_root_dir: ?[]const u8 = null;
/// TODO: Only available for builds targeting Windows
var slang_enable_nvapi: ?bool = null;
var nvapi_root_dir: ?[]const u8 = null;
/// TODO: Enable Aftermath in GFX, and add aftermath crash example to project
var slang_enable_aftermath: ?bool = null;
var aftermath_root_dir: ?[]const u8 = null;
var slang_enable_xlib: ?bool = null;

// Advanced Slang Build Options

/// TODO: Enable running the DX11 and DX12 tests on non-warning Windows platforms via vkd3d-proton, requires system-provided d3d headers
var slang_enable_dx_on_vk: bool = false;
/// TODO: Enable building and using slang-rhi for tests
var slang_enable_slang_rhi: bool = true;
// NOTE: SLANG_USE_SYSTEM_* and SLANG_SPIRV_HEADERS_INCLUDE_DIR have been elided as they are required.

// Debug Build Options

/// Whether to enable Debug printouts for the build script
var debug_build_script: bool = undefined;

// Options

fn setOptions(b: *std.Build) void {
    std.log.info("building with the following options:", .{});
}

fn createOption(b: *std.Build, comptime name: []const u8, comptime desc: []const u8) void {
    if (b.option(@FieldType(@This(), name), name, desc ++ ": default = " ++ std.fmt.comptimePrint("{}", @field(@This(), name)))) |value| @field(@This(), name) = value;
}

// Utilities

fn getVersion() []const u8 {
    comptime var version: []const u8 = undefined;
    comptime b: {
        const @"build.zig.zon" = @embedFile("build.zig.zon");
        var lines = std.mem.splitScalar(u8, @"build.zig.zon", '\n');
        while (lines.next()) |line| if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), ".version")) {
            var iter = std.mem.tokenizeScalar(u8, line, ' ');
            _ = iter.next();
            _ = iter.next();

            version = "v" ++ std.mem.trim(u8, iter.next().?, "\",");
            break :b;
        };
        unreachable;
    }
    return version;
}
