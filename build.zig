const std = @import("std");
const builtin = @import("builtin");
const SdlSdk = @import("sdl_zig");

const Platform = @This();
build: *std.Build,
sdl_sdk: *SdlSdk,

pub fn init(b: *std.Build) *Platform {
    const platform = b.allocator.create(Platform) catch @panic("out of memory");
    platform.* = .{ .build = b, .sdl_sdk = SdlSdk.init(b, null) };
    return platform;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const platform = Platform.init(b);
    const module = b.addModule("platform", .{
        .root_source_file = .{ .path = "src/sdl_platform.zig" },
        .imports = &.{
            .{ .name = "sdl2", .module = platform.sdl_sdk.getWrapperModule() },
        },
    });
    module.addIncludePath(.{ .path = "vendor/cimgui" });
    module.addIncludePath(.{ .path = "vendor/cimgui/generator/output" });
    module.addIncludePath(.{ .path = "vendor/glew" });

    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    const handmade_gl_pkg = b.dependency("handmade_gl", .{ .target = target, .optimize = optimize });
    example_exe.root_module.addImport("handmade_gl", handmade_gl_pkg.module("handmade_gl"));
    example_exe.root_module.addImport("sdl_platform", module);
    platform.link(example_exe);
    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the example application");
    run_step.dependOn(&run_cmd.step);
}

pub fn link(platform: *Platform, exe: *std.Build.Step.Compile) void {
    const b = platform.build;

    const cimgui_sdl2_opengl3_lib = b.addStaticLibrary(.{
        .name = "cimgui_sdl2_opengl3_lib",
        .target = exe.root_module.resolved_target.?,
        .optimize = exe.root_module.optimize.?,
        .link_libc = true,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_sdl2_opengl3_lib.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    cimgui_sdl2_opengl3_lib.defineCMacro("GLEW_NO_GLU", "");
    cimgui_sdl2_opengl3_lib.addIncludePath(.{ .path = "vendor/cimgui" });
    cimgui_sdl2_opengl3_lib.addIncludePath(.{ .path = "vendor/cimgui/generator/output" });
    cimgui_sdl2_opengl3_lib.addIncludePath(.{ .path = "vendor/cimgui/imgui" });
    cimgui_sdl2_opengl3_lib.addIncludePath(.{ .path = "vendor/cimgui/imgui/backends" });
    cimgui_sdl2_opengl3_lib.addIncludePath(.{ .path = "vendor/glew" });
    cimgui_sdl2_opengl3_lib.addCSourceFiles(.{
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
    cimgui_sdl2_opengl3_lib.linkLibCpp();
    if (cimgui_sdl2_opengl3_lib.rootModuleTarget().os.tag == .windows) {
        cimgui_sdl2_opengl3_lib.linkSystemLibrary("opengl32");
    } else {
        cimgui_sdl2_opengl3_lib.linkSystemLibrary("gl");
    }
    platform.sdl_sdk.link(cimgui_sdl2_opengl3_lib, .static);

    exe.linkLibrary(cimgui_sdl2_opengl3_lib);
}
