const std = @import("std");
const SdlSdk = @import("sdl_zig");

const Platform = @This();
build: *std.Build,
sdl_sdk: *SdlSdk,

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const platform = Platform.init(b);
    const platform_module = b.addModule("platform", .{
        .source_file = .{ .path = "src/sdl_platform.zig" },
        .dependencies = &.{
            .{ .name = "sdl2", .module = platform.sdl_sdk.getWrapperModule() },
        },
    });

    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "src/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    const handmade_gl_pkg = b.dependency("handmade_gl", .{ .target = target, .optimize = optimize });
    example_exe.addModule("handmade_gl", handmade_gl_pkg.module("handmade_gl"));
    example_exe.addModule("sdl_platform", platform_module);
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

pub fn init(b: *std.Build) *Platform {
    const platform = b.allocator.create(Platform) catch @panic("out of memory");
    platform.* = .{ .build = b, .sdl_sdk = SdlSdk.init(b, null) };
    return platform;
}

pub fn link(platform: *Platform, exe: *std.Build.LibExeObjStep) void {
    const b = platform.build;

    const cimgui_sdl2_opengl3_obj = b.addObject(.{
        .name = "cimgui_sdl2_opengl3_obj",
        .root_source_file = .{ .path = "vendor/cimgui/cimgui.cpp" },
        .target = exe.target,
        .optimize = exe.optimize,
    });
    // https://github.com/cimgui/cimgui/blob/261250f88f374e751b2de1501ba5c0c11e420b5a/backend_test/CMakeLists.txt#L39
    cimgui_sdl2_opengl3_obj.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    const root_dir = comptime blk: {
        break :blk std.fs.path.dirname(@src().file) orelse ".";
    };
    cimgui_sdl2_opengl3_obj.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui" });
    cimgui_sdl2_opengl3_obj.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui/generator/output" });
    cimgui_sdl2_opengl3_obj.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui/imgui" });
    cimgui_sdl2_opengl3_obj.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui/imgui/backends" });
    cimgui_sdl2_opengl3_obj.addCSourceFiles(.{ .files = &.{
        root_dir ++ "/vendor/cimgui/imgui/imgui.cpp",
        root_dir ++ "/vendor/cimgui/imgui/imgui_demo.cpp",
        root_dir ++ "/vendor/cimgui/imgui/imgui_draw.cpp",
        root_dir ++ "/vendor/cimgui/imgui/imgui_tables.cpp",
        root_dir ++ "/vendor/cimgui/imgui/imgui_widgets.cpp",
        root_dir ++ "/vendor/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
        root_dir ++ "/vendor/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
    } });
    cimgui_sdl2_opengl3_obj.linkLibC();
    cimgui_sdl2_opengl3_obj.linkLibCpp();
    cimgui_sdl2_opengl3_obj.linkSystemLibrary("gl");
    platform.sdl_sdk.link(cimgui_sdl2_opengl3_obj, .static);

    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui" });
    exe.addIncludePath(.{ .path = root_dir ++ "/vendor/cimgui/generator/output" });
    exe.addObject(cimgui_sdl2_opengl3_obj);
}
