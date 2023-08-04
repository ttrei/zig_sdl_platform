const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const FileSource = Build.FileSource;
const LibExeObjStep = Build.LibExeObjStep;
const SdlSdk = @import("sdl");

const Platform = @This();
build: *Build,
sdl_sdk: *SdlSdk,

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const handmade_gl_pkg = b.anonymousDependency(
        "vendor/handmade_gl",
        @import("vendor/handmade_gl/build.zig"),
        .{},
    );
    // Use this if decide to switch from vendoring to build.zig.zon
    // const handmade_gl_pkg = b.dependency("handmade_gl", .{});
    const handmade_gl_module = handmade_gl_pkg.module("handmade_gl");

    const sdk = Platform.init(b);

    var platform_module = b.addModule("platform", .{
        .source_file = FileSource.relative("src/sdl_platform.zig"),
        .dependencies = &.{
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
        .root_source_file = LazyPath.relative("vendor/cimgui/cimgui.cpp"),
        .target = exe.target,
        .optimize = exe.optimize,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_sdl2_opengl3_obj.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_sdl2_opengl3_obj.addIncludePath(LazyPath.relative("vendor/cimgui"));
    cimgui_sdl2_opengl3_obj.addIncludePath(LazyPath.relative("vendor/cimgui/generator/output"));
    cimgui_sdl2_opengl3_obj.addIncludePath(LazyPath.relative("vendor/cimgui/imgui"));
    cimgui_sdl2_opengl3_obj.addIncludePath(LazyPath.relative("vendor/cimgui/imgui/backends"));
    cimgui_sdl2_opengl3_obj.addCSourceFiles(&.{
        "vendor/cimgui/imgui/imgui.cpp",
        "vendor/cimgui/imgui/imgui_demo.cpp",
        "vendor/cimgui/imgui/imgui_draw.cpp",
        "vendor/cimgui/imgui/imgui_tables.cpp",
        "vendor/cimgui/imgui/imgui_widgets.cpp",
        "vendor/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
        "vendor/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
    }, &.{});
    cimgui_sdl2_opengl3_obj.linkLibC();
    cimgui_sdl2_opengl3_obj.linkLibCpp();
    cimgui_sdl2_opengl3_obj.linkSystemLibrary("gl");
    sdk.sdl_sdk.link(cimgui_sdl2_opengl3_obj, .static);

    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addIncludePath(LazyPath.relative("vendor/cimgui"));
    exe.addIncludePath(LazyPath.relative("vendor/cimgui/generator/output"));
    exe.addObject(cimgui_sdl2_opengl3_obj);
}
