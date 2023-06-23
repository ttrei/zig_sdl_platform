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

const TONE_A = 440.0;
const TONE_B = 440.0 * 3 / 4;

const PersistGlobal = struct {
    var show_demo_window: bool = false;
    var scale: f32 = 1;
    var tone_a: f64 = TONE_A;
    var tone_b: f64 = TONE_B;
    var tone_vol: f32 = 2000.0;
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

    // const p = &polygon.first.p;
    // p.* = geometry.scalePoint(p0, PersistGlobal.scale);
}

fn render(pixels: []u32, width: u32, height: u32) void {
    var buffer = ScreenBuffer{
        .width = width,
        .height = height,
        .pixels = pixels,
        .allocator = undefined,
    };
    buffer.clear(0x000000FF);
    const green = 0x00F000FF;
    const red = 0xFF0000FF;
    const yellow = 0xFFFF0FFF;
    _ = green;
    _ = yellow;

    polygon.draw(&buffer, red);

    _ = platform.c.igSliderFloat("scale", &PersistGlobal.scale, 0, 10, "%.02f", 0);
    platform.imguiText("Area: {d:.2}", .{polygon.area2()});
    platform.imguiText("A: {d:.2} Hz", .{PersistGlobal.tone_a});
    platform.imguiText("B: {d:.2} Hz", .{PersistGlobal.tone_b});

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
    const factor_a = (@floatFromInt(f64, input.controller_left_y) + 32768) / 32768;
    const factor_b = (@floatFromInt(f64, input.controller_right_y) + 32768) / 32768;
    PersistGlobal.tone_a = TONE_A * factor_a;
    PersistGlobal.tone_b = TONE_B * factor_b;
    // std.debug.print("{d}\t{d}\n", .{ input.controller_left_x, input.controller_left_y });
}

fn writeAudio(buffer: *ApplicationAudioBuffer) void {
    const Persist = struct {
        var phase_a: f64 = 0.0;
        var phase_b: f64 = 0.0;
    };

    const period_a = @floatFromInt(f32, AudioSettings.sample_rate) / PersistGlobal.tone_a;
    const period_b = @floatFromInt(f32, AudioSettings.sample_rate) / PersistGlobal.tone_b;
    const two_pi = 2 * std.math.pi;

    const frame_count = buffer.sample_count / AudioSettings.channel_count;

    var i: u32 = 0;
    while (i < frame_count) {
        const amplitude_a = std.math.sin(Persist.phase_a) * PersistGlobal.tone_vol;
        const amplitude_b = std.math.sin(Persist.phase_b) * PersistGlobal.tone_vol;
        const sample_value = @intFromFloat(i16, amplitude_a + amplitude_b);
        var j: u8 = 0;
        while (j < AudioSettings.channel_count) {
            buffer.samples[AudioSettings.channel_count * i + j] = sample_value;
            j += 1;
        }
        Persist.phase_a = @mod(Persist.phase_a + two_pi / period_a, two_pi);
        Persist.phase_b = @mod(Persist.phase_b + two_pi / period_b, two_pi);
        i += 1;
    }
}
