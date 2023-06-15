const std = @import("std");

const platform = @import("sdl_platform");
const InputState = platform.InputState;
const ApplicationAudioBuffer = platform.ApplicationAudioBuffer;
const AudioSettings = platform.AudioSettings;

const gl = @import("handmade_gl");
const ScreenBuffer = gl.screen.ScreenBuffer;
const geometry = gl.geometry;
const Polygon = geometry.Polygon;
const Point = geometry.Point;

var polygon: Polygon = undefined;

const PersistGlobal = struct {
    var show_demo_window: bool = false;
    var scale: f32 = 1;
    var tone_hz: f64 = 440.0;
    var tone_vol: f32 = 3000.0;
};

const p0 = Point{ .x = 100, .y = 100 };

pub fn main() !void {
    polygon = Polygon.init();
    defer polygon.deinit();
    try polygon.add_vertex(p0);
    // try polygon.add_vertex(Point{ .x = 200, .y = 100 });
    // try polygon.add_vertex(Point{ .x = 300, .y = 300 });

    try platform.coreLoop(update, render, resize, processInput, writeAudio);
}

fn update(step: f64) void {
    _ = step;
    // PersistGlobal.tone_hz *= 1.0005;
    PersistGlobal.tone_hz *= 0.9995;

    // const p = &polygon.first.p;
    // p.* = geometry.scalePoint(p0, PersistGlobal.scale);
}

fn render(buffer: *ScreenBuffer) void {
    buffer.clear(0x000000FF);
    const green = 0x00F000FF;
    const red = 0xFF0000FF;
    const yellow = 0xFFFF0FFF;
    _ = green;
    _ = yellow;

    polygon.draw(buffer, red);

    _ = platform.c.igSliderFloat("scale", &PersistGlobal.scale, 0, 10, "%.02f", 0);
    platform.imguiText("Area: {d:.2}", .{polygon.area2()});

    if (PersistGlobal.show_demo_window) platform.c.igShowDemoWindow(&PersistGlobal.show_demo_window);
}

fn resize(width: u32, height: u32) void {
    _ = width;
    _ = height;
}

fn processInput(input: *const InputState) void {
    if (input.mouse_left_down) {
        polygon.add_vertex(Point{ .x = input.mouse_x, .y = input.mouse_y }) catch unreachable;
    }
    polygon.first.prev.p = Point{ .x = input.mouse_x, .y = input.mouse_y };
}

fn writeAudio(buffer: *ApplicationAudioBuffer) void {
    const Persist = struct {
        var phase: f64 = 0.0;
    };

    const period = @intToFloat(f32, AudioSettings.sample_rate) / PersistGlobal.tone_hz;
    const two_pi = 2 * std.math.pi;

    const frame_count = buffer.sample_count / AudioSettings.channel_count;

    var i: u32 = 0;
    while (i < frame_count) {
        const sample_value = @floatToInt(i16, std.math.sin(Persist.phase) * PersistGlobal.tone_vol);
        var j: u8 = 0;
        while (j < AudioSettings.channel_count) {
            buffer.samples[AudioSettings.channel_count * i + j] = sample_value;
            j += 1;
        }
        Persist.phase = @mod(Persist.phase + two_pi / period, two_pi);
        i += 1;
    }
}
