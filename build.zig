const std = @import("std");
const sdl = @import("sdl");

const FileSource = std.build.FileSource;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_sdk = sdl.init(b, null);

    const cimgui_obj = b.addObject(.{
        .name = "cimgui",
        .root_source_file = FileSource.relative("deps/cimgui/cimgui.cpp"),
        .target = target,
        .optimize = optimize,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_obj.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_obj.addIncludePath("deps/cimgui");
    cimgui_obj.addIncludePath("deps/cimgui/generator/output");
    cimgui_obj.addIncludePath("deps/cimgui/imgui");
    cimgui_obj.addIncludePath("deps/cimgui/imgui/backends");
    // cimgui_obj.addCSourceFiles(&.{
    //     // "deps/cimgui/cimgui.cpp",
    //     "deps/cimgui/imgui/imgui.cpp",
    //     "deps/cimgui/imgui/imgui_demo.cpp",
    //     "deps/cimgui/imgui/imgui_draw.cpp",
    //     "deps/cimgui/imgui/imgui_tables.cpp",
    //     "deps/cimgui/imgui/imgui_widgets.cpp",
    //     "deps/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
    //     "deps/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
    // }, &.{});
    cimgui_obj.linkLibC();
    cimgui_obj.linkLibCpp();
    sdl_sdk.link(cimgui_obj, .static);

    const handmade_gl_pkg = b.dependency("handmade_gl", .{});
    const handmade_gl_module = handmade_gl_pkg.module("handmade_gl");

    var platform_lib = b.addSharedLibrary(.{
        .name = "platform_lib",
        .root_source_file = FileSource.relative("src/sdl_platform.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform_lib.addModule("handmade_gl", handmade_gl_module);
    platform_lib.addIncludePath("deps/cimgui");
    platform_lib.addIncludePath("deps/cimgui/generator/output");
    platform_lib.addIncludePath("deps/cimgui/imgui");
    platform_lib.addIncludePath("deps/cimgui/imgui/backends");
    platform_lib.linkLibC();
    platform_lib.addObject(cimgui_obj);
    platform_lib.linkSystemLibrary("gl");
    sdl_sdk.link(platform_lib, .dynamic);

    _ = b.addModule("platform", .{
        .source_file = FileSource.relative("src/sdl_platform.zig"),
        .dependencies = &.{
            .{ .name = "handmade_gl", .module = handmade_gl_module },
        },
    });
}
