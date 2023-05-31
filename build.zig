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
    cimgui_obj.addCSourceFiles(&.{
        "deps/cimgui/imgui/imgui.cpp",
        "deps/cimgui/imgui/imgui_demo.cpp",
        "deps/cimgui/imgui/imgui_draw.cpp",
        "deps/cimgui/imgui/imgui_tables.cpp",
        "deps/cimgui/imgui/imgui_widgets.cpp",
        "deps/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
        "deps/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
    }, &.{});
    cimgui_obj.linkLibC();
    cimgui_obj.linkLibCpp();
    sdl_sdk.link(cimgui_obj, .static);

    const handmade_gl_pkg = b.dependency("handmade_gl", .{});
    const handmade_gl_module = handmade_gl_pkg.module("handmade_gl");

    var platform_module = b.addModule("platform", .{
        .source_file = FileSource.relative("src/sdl_platform.zig"),
        .dependencies = &.{
            .{ .name = "handmade_gl", .module = handmade_gl_module },
            .{ .name = "sdl2", .module = sdl_sdk.getWrapperModule() },
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
    example_exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    example_exe.addIncludePath("deps/cimgui");
    example_exe.addIncludePath("deps/cimgui/generator/output");
    example_exe.addObject(cimgui_obj);
    example_exe.linkLibC();
    example_exe.linkSystemLibrary("gl");
    // TODO try to get rid of this - the application shouldn't care about SDL
    // Probably need to define our own "link" function.
    sdl_sdk.link(example_exe, .dynamic);

    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the example application");
    run_step.dependOn(&run_cmd.step);
}
