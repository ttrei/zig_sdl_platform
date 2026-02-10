const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");

const Platform = @This();
builder: *std.Build,
sdk: *sdl,

pub fn init(b: *std.Build) *Platform {
    const platform = b.allocator.create(Platform) catch @panic("out of memory");
    platform.* = .{ .builder = b, .sdk = sdl.init(b, .{}) };
    return platform;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const platform = Platform.init(b);
    const module = b.addModule("platform", .{
        .root_source_file = b.path("src/sdl_platform.zig"),
        .imports = &.{
            .{ .name = "sdl2", .module = platform.sdk.getWrapperModule() },
        },
    });
    module.addIncludePath(b.path("vendor/cimgui"));
    module.addIncludePath(b.path("vendor/cimgui/generator/output"));
    module.addIncludePath(b.path("vendor/glew"));

    const example_mod = b.createModule(.{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_module = example_mod,
    });
    const handmade_gl_pkg = b.dependency("handmade_gl", .{ .target = target, .optimize = optimize });
    example_mod.addImport("handmade_gl", handmade_gl_pkg.module("handmade_gl"));
    example_mod.addImport("sdl_platform", module);
    platform.link(example_exe);
    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the example application");
    run_step.dependOn(&run_cmd.step);

    // Regression test: @cImport of cimgui.h crashes Zig 0.15.2 compiler.
    // Run `zig build test-cimport` to check if a future Zig version fixes this.
    // See src/test_cimport.zig for investigation details.
    const test_cimport_mod = b.createModule(.{
        .root_source_file = b.path("src/test_cimport.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_cimport_mod.addIncludePath(b.path("vendor/cimgui"));
    test_cimport_mod.addIncludePath(b.path("vendor/cimgui/generator/output"));
    const test_cimport_exe = b.addExecutable(.{
        .name = "test_cimport",
        .root_module = test_cimport_mod,
    });
    const test_cimport_step = b.step("test-cimport", "Test @cImport of cimgui.h (crashes on Zig 0.15.2)");
    test_cimport_step.dependOn(&test_cimport_exe.step);
}

pub fn link(platform: *Platform, exe: *std.Build.Step.Compile) void {
    const b = platform.builder;

    const cimgui_mod = b.createModule(.{
        .target = exe.root_module.resolved_target.?,
        .optimize = exe.root_module.optimize.?,
        .link_libc = true,
    });
    const cimgui_sdl2_opengl3_lib = b.addLibrary(.{
        .name = "cimgui_sdl2_opengl3_lib",
        .linkage = .static,
        .root_module = cimgui_mod,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_mod.addCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_mod.addCMacro("GLEW_NO_GLU", "");
    cimgui_mod.addIncludePath(b.path("vendor/cimgui"));
    cimgui_mod.addIncludePath(b.path("vendor/cimgui/generator/output"));
    cimgui_mod.addIncludePath(b.path("vendor/cimgui/imgui"));
    cimgui_mod.addIncludePath(b.path("vendor/cimgui/imgui/backends"));
    cimgui_mod.addIncludePath(b.path("vendor/glew"));
    cimgui_mod.addCSourceFiles(.{
        .files = &.{
            "vendor/cimgui/cimgui.cpp",
            "vendor/cimgui/imgui/imgui.cpp",
            "vendor/cimgui/imgui/imgui_demo.cpp",
            "vendor/cimgui/imgui/imgui_draw.cpp",
            "vendor/cimgui/imgui/imgui_tables.cpp",
            "vendor/cimgui/imgui/imgui_widgets.cpp",
            "vendor/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
            "vendor/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
            "vendor/glew/glew.c",
        },
    });
    cimgui_mod.link_libcpp = true;
    if (cimgui_sdl2_opengl3_lib.rootModuleTarget().os.tag == .windows) {
        cimgui_mod.linkSystemLibrary("opengl32", .{});
    } else {
        cimgui_mod.linkSystemLibrary("gl", .{});
    }
    platform.sdk.link(cimgui_sdl2_opengl3_lib, .static, .SDL2);

    exe.root_module.linkLibrary(cimgui_sdl2_opengl3_lib);
    // This seems necessary only on windows
    platform.sdk.link(exe, .static, .SDL2);
}
