const std = @import("std");

const platform = @import("sdl_platform");
const gl = @import("handmade_gl");
const ScreenBuffer = gl.screen.ScreenBuffer;

const geometry = gl.geometry;
const Polygon = geometry.Polygon;
const Point = geometry.Point;

var polygon: Polygon = undefined;

const S = struct {
    var show_demo_window: bool = false;
    var scale: f32 = 1;
};

const p0 = Point{ .x = 100, .y = 100 };

pub fn main() !void {
    polygon = Polygon.init();
    defer polygon.deinit();
    try polygon.add_vertex(p0);
    // try polygon.add_vertex(Point{ .x = 200, .y = 100 });
    // try polygon.add_vertex(Point{ .x = 300, .y = 300 });

    try platform.coreLoop(update, render, resize, processInput);
}

fn update(step: f64) void {
    _ = step;

    // const p = &polygon.first.p;
    // p.* = geometry.scalePoint(p0, S.scale);
}

fn render(buffer: *ScreenBuffer) void {
    buffer.clear(0x000000FF);
    const green = 0x00F000FF;
    const red = 0xFF0000FF;
    const yellow = 0xFFFF0FFF;
    _ = green;
    _ = yellow;

    polygon.draw(buffer, red);

    _ = platform.c.igSliderFloat("scale", &S.scale, 0, 10, "%.02f", 0);
    platform.imguiText("Area: {d:.2}", .{polygon.area2()});

    if (S.show_demo_window) platform.c.igShowDemoWindow(&S.show_demo_window);
}

fn resize(width: u32, height: u32) void {
    _ = width;
    _ = height;
}

fn processInput(input: *const platform.InputState) void {
    if (input.mouse_left_down) {
        polygon.add_vertex(Point{ .x = input.mouse_x, .y = input.mouse_y }) catch unreachable;
    }
    polygon.first.prev.p = Point{ .x = input.mouse_x, .y = input.mouse_y };
}
