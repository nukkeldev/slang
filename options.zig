const std = @import("std");

// Standard Build Options

target: std.Build.ResolvedTarget = undefined,
optimize: std.builtin.OptimizeMode = undefined,

// Slang Build Options

// Taken from https://github.com/shader-slang/slang/blob/master/docs/building.md#cmake-options.

/// The project version, if not specified, from build.zig.zon
slang_version: []const u8,
/// TODO: Build slang with an embedded version of the core module
slang_embed_core_module: bool,
/// TODO: Embed the core module source in the binary
slang_embed_core_module_source: bool,
/// TODO: Enable generating DXIL using DXC
slang_enable_dxil: bool,
/// TODO: Enable ASAN (address sanitizer)
slang_enable_asan: bool,
/// TODO: Enable full IR validation (SLOW!)
slang_enable_full_ir_validation: bool,
/// TODO: Enable IR BreakAlloc functionality for debugging
slang_enable_ir_break_alloc: bool,
/// TODO: Enable gfx targets
slang_enable_gfx: bool,
/// TODO: Enable language server target
slang_enable_slangd: bool,
/// TODO: Enable standalone compiler target
slang_enable_slangc: bool,
/// TODO: Enable Slang interpreter target
slang_enable_slangi: bool,
/// TODO: Enable runtime target
slang_enable_slangrt: bool,
/// TODO: Enable glslang dependency and slang-glslang wrapper target
slang_enable_slang_glslang: bool,
/// TODO: Enable test targets, requires `slang_enable_gfx`, `slang_enable_slangd` and `slang_enable_slangrt`
slang_enable_tests: bool,
/// TODO: Enable example targets, requires `slang_enable_gfx`
slang_enable_examples: bool,
/// How to build the slang library
slang_lib_type: std.builtin.LinkMode,
/// TODO: Enable generating debug info for Release configs
slang_enable_release_debug_info: bool,
/// TODO: Enable LTO for Release builds
slang_enable_release_lto: bool,
/// TODO: Enable generating split debug info for Debug and RelWithDebInfo configs
slang_enable_split_debug_info: bool,
/// TODO: How to set up llvm support
slang_slang_llvm_flavor: []const u8, // TODO: Enum
/// TODO: URL specifying the location of the slang-llvm prebuilt library
slang_slang_llvm_binary_url: []const u8, // TODO: Depends on target system.
/// TODO: Path to an installed generator target binaries for cross compilation
slang_generators_path: []const u8, // TODO: Remove this.

// Optional Dependency Build Options

// The following options relate to optional dependencies for additional backends and running additional tests.
// Left unchanged they are auto detected, however they can be set to OFF to prevent their usage, or set to ON
// to make it an error if they can't be found.

/// TODO: Enable running tests with the CUDA backend, doesn't affect the targets Slang itself supports
slang_enable_cuda: @"?bool",
cudatoolkit_root: []const u8,
cuda_path: []const u8,
/// TODO: Requires CUDA
slang_enable_optix: @"?bool",
optix_root_dir: []const u8,
/// TODO: Only available for builds targeting Windows
slang_enable_nvapi: @"?bool",
nvapi_root_dir: []const u8,
/// TODO: Enable Aftermath in GFX, and add aftermath crash example to project
slang_enable_aftermath: @"?bool",
aftermath_root_dir: []const u8,
slang_enable_xlib: @"?bool",

// Advanced Slang Build Options

/// TODO: Enable running the DX11 and DX12 tests on non-warning Windows platforms via vkd3d-proton, requires system-provided d3d headers
slang_enable_dx_on_vk: bool,
/// TODO: Enable building and using slang-rhi for tests
slang_enable_slang_rhi: bool,
// NOTE: SLANG_USE_SYSTEM_* and SLANG_SPIRV_HEADERS_INCLUDE_DIR have been elided as they are required.

// Debug Build Options

/// Whether to enable Debug printouts for the build script
debug_build_script: bool,

// Options

pub fn init(b: *std.Build) !*@This() {
    const self = try b.allocator.create(@This());
    self.* = .{
        // Standard Build Options
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        // Slang Build Options
        .slang_version = createOption(b, "slang_version", "The project version, if not specified, from build.zig.zon", getVersion(b.allocator)),
        .slang_embed_core_module = createOption(b, "slang_embed_core_module", "TODO: Build slang with an embedded version of the core module", true),
        .slang_embed_core_module_source = createOption(b, "slang_embed_core_module_source", "TODO: Embed the core module source in the binary", true),
        .slang_enable_dxil = createOption(b, "slang_enable_dxil", "TODO: Enable generating DXIL using DXC", true),
        .slang_enable_asan = createOption(b, "slang_enable_asan", "TODO: Enable ASAN (address sanitizer)", false),
        .slang_enable_full_ir_validation = createOption(b, "slang_enable_full_ir_validation", "TODO: Enable full IR validation (SLOW!)", false),
        .slang_enable_ir_break_alloc = createOption(b, "slang_enable_ir_break_alloc", "TODO: Enable IR BreakAlloc functionality for debugging", false),
        .slang_enable_gfx = createOption(b, "slang_enable_gfx", "TODO: Enable gfx targets", true),
        .slang_enable_slangd = createOption(b, "slang_enable_slangd", "TODO: Enable language server target", true),
        .slang_enable_slangc = createOption(b, "slang_enable_slangc", "TODO: Enable standalone compiler target", true),
        .slang_enable_slangi = createOption(b, "slang_enable_slangi", "TODO: Enable Slang interpreter target", true),
        .slang_enable_slangrt = createOption(b, "slang_enable_slangrt", "TODO: Enable runtime target", true),
        .slang_enable_slang_glslang = createOption(b, "slang_enable_slang_glslang", "TODO: Enable glslang dependency and slang-glslang wrapper target", true),
        .slang_enable_tests = createOption(b, "slang_enable_tests", "TODO: Enable test targets, requires `slang_enable_gfx`, `slang_enable_slangd` and `slang_enable_slangrt`", true),
        .slang_enable_examples = createOption(b, "slang_enable_examples", "TODO: Enable example targets, requires SLANG_ENABLE_GFX", true),
        // NOTE: This was changed from the original .dynamic default.
        .slang_lib_type = createOption(b, "slang_lib_type", "How to build the slang library", .static),
        .slang_enable_release_debug_info = createOption(b, "slang_enable_release_debug_info", "TODO: Enable generating debug info for Release configs", true),
        .slang_enable_release_lto = createOption(b, "slang_enable_release_lto", "TODO: Enable LTO for Release builds", true),
        .slang_enable_split_debug_info = createOption(b, "slang_enable_split_debug_info", "TODO: Enable generating split debug info for Debug and RelWithDebInfo configs", true),
        .slang_slang_llvm_flavor = createOption(b, "slang_slang_llvm_flavor", "TODO: How to set up llvm support", "FETCH_BINARY_IF_POSSIBLE"),
        .slang_slang_llvm_binary_url = createOption(b, "slang_slang_llvm_binary_url", "URL specifying the location of the slang-llvm prebuilt library", ""),
        .slang_generators_path = createOption(b, "slang_generators_path", "TODO: Path to an installed generator target binaries for cross compilation", ""),
        // Optional Dependency Build Options
        .slang_enable_cuda = createOption(b, "slang_enable_cuda", "TODO: Enable running tests with the CUDA backend, doesn't affect the targets Slang itself supports", .null),
        .cudatoolkit_root = createOption(b, "cudatoolkit_root", "", ""),
        .cuda_path = createOption(b, "cuda_path", "", ""),
        .slang_enable_optix = createOption(b, "slang_enable_optix", "TODO: Requires CUDA", .null),
        .optix_root_dir = createOption(b, "optix_root_dir", "", ""),
        .slang_enable_nvapi = createOption(b, "slang_enable_nvapi", "TODO: Only available for builds targeting Windows", .null),
        .nvapi_root_dir = createOption(b, "nvapi_root_dir", "", ""),
        .slang_enable_aftermath = createOption(b, "slang_enable_aftermath", "TODO: Enable Aftermath in GFX, and add aftermath crash example to project", .null),
        .aftermath_root_dir = createOption(b, "aftermath_root_dir", "", ""),
        .slang_enable_xlib = createOption(b, "slang_enable_xlib", "", .null),
        // Advanced Slang Build Options
        .slang_enable_dx_on_vk = createOption(b, "slang_enable_dx_on_vk", "TODO: Enable running the DX11 and DX12 tests on non-warning Windows platforms via vkd3d-proton, requires system-provided d3d headers", false),
        .slang_enable_slang_rhi = createOption(b, "slang_enable_slang_rhi", "TODO: Enable building and using slang-rhi for tests", true),
        // Debug Build Options
        .debug_build_script = createOption(b, "debug_build_script", "Whether to enable Debug printouts for the build script", false),
    };

    std.log.info("building with the following options:", .{});
    inline for (@typeInfo(@This()).@"struct".fields) |field| {
        std.log.info("\t{s}=" ++ comptime createOptionValueFormatString(field.type), .{ field.name, @field(self, field.name) });
    }

    return self;
}

fn createOption(b: *std.Build, comptime name: []const u8, comptime desc: []const u8, default_value: anytype) @FieldType(@This(), name) {
    const field_type = @FieldType(@This(), name);
    const desc_fmt = "{s} [default=" ++ comptime createOptionValueFormatString(field_type) ++ "]";

    const desc_with_default = std.fmt.allocPrint(b.allocator, desc_fmt, .{ desc, default_value }) catch @panic("OOM");
    return b.option(field_type, name, desc_with_default) orelse default_value;
}

fn createOptionValueFormatString(comptime field_type: type) []const u8 {
    const f = struct {
        fn f(comptime ty: type) []const u8 {
            return switch (@typeInfo(ty)) {
                .pointer => |p| if (p.child == u8) "s" else "",
                .optional => |o| "?" ++ f(o.child),
                else => "",
            };
        }
    }.f;

    return "{" ++ comptime f(field_type) ++ "}";
}

// Utilities

const @"build.zig.zon" = @embedFile("build.zig.zon");

fn getVersion(allocator: std.mem.Allocator) []const u8 {
    var lines = std.mem.splitScalar(u8, @"build.zig.zon", '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), ".version")) {
        var iter = std.mem.tokenizeScalar(u8, line, ' ');
        _ = iter.next();
        _ = iter.next();
        return std.fmt.allocPrint(allocator, "v{s}", .{std.mem.trim(u8, iter.next().?, "\",")}) catch @panic("OOM");
    };
    unreachable;
}

// TODO: Intercept this when creating an option into a ?bool
pub const @"?bool" = enum { null, true, false };
