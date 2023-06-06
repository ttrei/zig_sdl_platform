const std = @import("std");
const Build = std.Build;
const FileSource = Build.FileSource;
const LibExeObjStep = Build.LibExeObjStep;
const SdlSdk = @import("sdl");

const Platform = @This();
build: *Build,
sdl_sdk: *SdlSdk,

// Given a path relative to this repository root, return the respective absolute path.
// This is a way to get access to the vendored cimgui headers from application code.
// TODO: Delete this hack when following issue is solved:
// https://github.com/ziglang/zig/issues/14719
// There's a pull request:
// https://github.com/ziglang/zig/pull/14731
fn sdkPath(comptime path: []const u8) []const u8 {
    if (path[0] == '/') @compileError("sdkPath requires a relative path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ "/" ++ path;
    };
}

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const handmade_gl_pkg = b.dependency("handmade_gl", .{});
    const handmade_gl_module = handmade_gl_pkg.module("handmade_gl");

    const sdk = Platform.init(b);

    var platform_module = b.addModule("platform", .{
        .source_file = FileSource.relative("src/sdl_platform.zig"),
        .dependencies = &.{
            .{ .name = "handmade_gl", .module = handmade_gl_module },
            .{ .name = "sdl2", .module = sdk.sdl_sdk.getWrapperModule() },
        },
    });

    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = FileSource.relative("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_exe.addModule("handmade_gl", handmade_gl_module);
    example_exe.addModule("sdl_platform", platform_module);
    sdk.link(example_exe);

    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the example application");
    run_step.dependOn(&run_cmd.step);
}

pub fn init(b: *Build) *Platform {
    const sdk = b.allocator.create(Platform) catch @panic("out of memory");
    sdk.* = .{
        .build = b,
        .sdl_sdk = SdlSdk.init(b, null),
    };
    return sdk;
}

pub fn link(sdk: *Platform, exe: *LibExeObjStep) void {
    const b = sdk.build;

    const cimgui_sdl2_opengl3_obj = b.addObject(.{
        .name = "cimgui_sdl2_opengl3_obj",
        .root_source_file = FileSource{ .path = sdkPath("vendor/cimgui/cimgui.cpp") },
        .target = exe.target,
        .optimize = exe.optimize,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_sdl2_opengl3_obj.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_sdl2_opengl3_obj.addIncludePath(sdkPath("vendor/cimgui"));
    cimgui_sdl2_opengl3_obj.addIncludePath(sdkPath("vendor/cimgui/generator/output"));
    cimgui_sdl2_opengl3_obj.addIncludePath(sdkPath("vendor/cimgui/imgui"));
    cimgui_sdl2_opengl3_obj.addIncludePath(sdkPath("vendor/cimgui/imgui/backends"));
    cimgui_sdl2_opengl3_obj.addCSourceFiles(&.{
        sdkPath("vendor/cimgui/imgui/imgui.cpp"),
        sdkPath("vendor/cimgui/imgui/imgui_demo.cpp"),
        sdkPath("vendor/cimgui/imgui/imgui_draw.cpp"),
        sdkPath("vendor/cimgui/imgui/imgui_tables.cpp"),
        sdkPath("vendor/cimgui/imgui/imgui_widgets.cpp"),
        sdkPath("vendor/cimgui/imgui/backends/imgui_impl_sdl2.cpp"),
        sdkPath("vendor/cimgui/imgui/backends/imgui_impl_opengl3.cpp"),
    }, &.{});
    cimgui_sdl2_opengl3_obj.linkLibC();
    cimgui_sdl2_opengl3_obj.linkLibCpp();
    cimgui_sdl2_opengl3_obj.linkSystemLibrary("gl");
    sdk.sdl_sdk.link(cimgui_sdl2_opengl3_obj, .static);

    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addIncludePath(sdkPath("vendor/cimgui"));
    exe.addIncludePath(sdkPath("vendor/cimgui/generator/output"));
    exe.addObject(cimgui_sdl2_opengl3_obj);
}
