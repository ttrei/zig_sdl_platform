const std = @import("std");

const Build = std.Build;
const FileSource = Build.FileSource;
const LibExeObjStep = Build.LibExeObjStep;

const SdlSdk = @import("sdl");

const PlatformSdk = @This();

build: *Build,
sdl_sdk: *SdlSdk,

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const handmade_gl_pkg = b.dependency("handmade_gl", .{});
    const handmade_gl_module = handmade_gl_pkg.module("handmade_gl");

    const sdk = PlatformSdk.init(b);

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

pub fn init(b: *Build) *PlatformSdk {
    const sdk = b.allocator.create(PlatformSdk) catch @panic("out of memory");

    sdk.* = .{
        .build = b,
        .sdl_sdk = SdlSdk.init(b, null),
    };

    return sdk;
}

pub fn link(sdk: *PlatformSdk, exe: *LibExeObjStep) void {
    const b = sdk.build;

    const cimgui_lib = b.addStaticLibrary(.{
        .name = "cimgui_lib",
        .root_source_file = FileSource.relative("deps/cimgui/cimgui.cpp"),
        .target = exe.target,
        .optimize = exe.optimize,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_lib.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_lib.addIncludePath("deps/cimgui");
    cimgui_lib.addIncludePath("deps/cimgui/generator/output");
    cimgui_lib.addIncludePath("deps/cimgui/imgui");
    cimgui_lib.addIncludePath("deps/cimgui/imgui/backends");
    cimgui_lib.addCSourceFiles(&.{
        "deps/cimgui/imgui/imgui.cpp",
        "deps/cimgui/imgui/imgui_demo.cpp",
        "deps/cimgui/imgui/imgui_draw.cpp",
        "deps/cimgui/imgui/imgui_tables.cpp",
        "deps/cimgui/imgui/imgui_widgets.cpp",
        "deps/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
        "deps/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
    }, &.{});
    cimgui_lib.linkLibC();
    cimgui_lib.linkLibCpp();
    sdk.sdl_sdk.link(cimgui_lib, .static);
    // b.installArtifact(cimgui_lib);

    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addIncludePath("deps/cimgui");
    exe.addIncludePath("deps/cimgui/generator/output");
    exe.linkLibrary(cimgui_lib);

    exe.linkLibC();
    exe.linkSystemLibrary("gl");
    sdk.sdl_sdk.link(exe, .dynamic);
}
