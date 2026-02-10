// Minimal reproducer for Zig 0.15.2 compiler segfault with @cImport of cimgui.h.
//
// Run: zig build test-cimport
// If this compiles successfully, the bug is fixed in the current Zig version.
//
// Investigation results (Zig 0.15.2, 2026-02-10):
// - @cImport of cimgui.h crashes the compiler regardless of other modules
// - The crash is NOT specific to SDL.zig's getWrapperModule() or getNativeModule()
// - Small @cImport (e.g., stdio.h) works fine, even combined with SDL.zig
// - zig translate-c works fine on the same header (5400+ lines output)
// - The crash is in the @cImport pipeline, not in translate-c itself
// - Workaround: hand-written extern declarations in c_bindings.zig

const std = @import("std");
const cimgui = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});
    @cInclude("cimgui.h");
});

pub fn main() void {
    _ = cimgui.igCreateContext;
    std.debug.print("SUCCESS: @cImport of cimgui.h compiled without crash!\n", .{});
}
