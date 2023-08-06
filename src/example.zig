const std = @import("std");

const platform = @import("sdl_platform");
const InputState = platform.InputState;
const ApplicationAudioBuffer = platform.ApplicationAudioBuffer;
const AudioSettings = platform.AudioSettings;

const gl = @import("handmade_gl");
const Pixel = gl.screen.Pixel;
const ScreenCoordinate = gl.screen.ScreenCoordinate;
const PixelBuffer = gl.screen.PixelBuffer;
const geometry = gl.geometry;
const Polygon = geometry.Polygon;
const Rectangle = geometry.Rectangle;
const Circle = geometry.Circle;
const Shape = geometry.Shape;
const PointInt = geometry.PointInt;

pub const CoordinateTransform = gl.geometry.CoordinateTransform;

const TONE_A = 440.0;
const TONE_B = 440.0 * 3 / 4;

const red = 0xFF0000FF;
const green = 0x00FF00FF;
const blue = 0x0000FFFF;
const yellow = 0xFFFF00FF;

const PersistGlobal = struct {
    var show_demo_window: bool = false;
    var scale: f32 = 1.0;
    var tone_a: f64 = TONE_A;
    var tone_b: f64 = TONE_B;
    var tone_vol: f32 = 2000.0;

    var buffer: PixelBuffer = undefined;
    var scene: Scene = undefined;
    var viewport: ViewPort = undefined;
    var viewport_pos = Pixel{ .x = 50, .y = 50 };
};

const ViewPort = struct {
    // Transforms from scene coordinates to viewport coordinates
    camera_transform: CoordinateTransform,
    buffer: PixelBuffer,
};

const Scene = struct {
    objects: std.ArrayList(*Shape) = undefined,
    current_polygon: *Polygon = undefined,
    rectangle: ?Rectangle = null,
    obj: ?Shape = null,
    arena: std.heap.ArenaAllocator = undefined,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            // .objects = std.ArrayList(*Shape).init(arena.allocator()),
            .objects = std.ArrayList(*Shape).init(std.heap.page_allocator),
        };
    }
    pub fn deinit(self: *Self) void {
        self.objects.deinit();
        self.arena.deinit();
    }

    pub fn addPolygon(self: *Self) !*Polygon {
        var shape = try self.arena.allocator().create(Shape);
        shape.* = .{ .polygon = Polygon.init(self.arena.allocator()) };
        try self.objects.append(shape);
        return &shape.polygon;
    }

    pub fn draw(self: *const Self, viewport: *ViewPort) void {
        for (self.objects.items) |o| {
            o.polygon.draw(&viewport.buffer, green, &viewport.camera_transform);
        }
        if (self.rectangle != null) {
            self.rectangle.?.draw(&viewport.buffer, red, &viewport.camera_transform);
        }
        if (self.obj != null) {
            self.obj.?.circle.draw(&viewport.buffer, yellow, &viewport.camera_transform);
        }
    }
};

pub fn main() !void {
    PersistGlobal.scene = Scene.init();
    defer PersistGlobal.scene.deinit();

    PersistGlobal.scene.current_polygon = try PersistGlobal.scene.addPolygon();
    PersistGlobal.scene.rectangle = Rectangle{ .p1 = .{ .x = 30, .y = 30 }, .p2 = .{ .x = 200, .y = 300 } };
    PersistGlobal.scene.obj = Shape{
        .circle = Circle{ .c = .{ .x = 70, .y = 150 }, .r = 60 },
    };

    try platform.coreLoop(update, render, resize, processInput, writeAudio);
}

fn update(step: f64) void {
    _ = step;

    PersistGlobal.viewport.camera_transform.scale = PersistGlobal.scale;

    // const poly = PersistGlobal.scene.objects.getLast().polygon;
    // if (poly.n > 0) {
    //     const p = &poly.first.p;
    //     _ = p;
    // }
}

fn render() void {
    PersistGlobal.buffer.clear(0xFFFFFFFF);
    PersistGlobal.viewport.buffer.clear(0x000000FF);

    PersistGlobal.scene.draw(&PersistGlobal.viewport);

    _ = platform.c.igSliderFloat("scale", &PersistGlobal.scale, 0.5, 1.5, "%.02f", 0);
    // platform.imguiText("Area: {d:.2}", .{poly.area2()});
    platform.imguiText("A: {d:.2} Hz", .{PersistGlobal.tone_a});
    platform.imguiText("B: {d:.2} Hz", .{PersistGlobal.tone_b});

    if (PersistGlobal.show_demo_window) platform.c.igShowDemoWindow(&PersistGlobal.show_demo_window);
}

fn updateViewPort() void {
    const viewport_width = PersistGlobal.buffer.width * 8 / 10;
    const viewport_height = PersistGlobal.buffer.height * 8 / 10;
    if (PersistGlobal.viewport_pos.x + viewport_width > PersistGlobal.buffer.width) {
        PersistGlobal.viewport_pos.x = PersistGlobal.buffer.width - viewport_width;
    }
    if (PersistGlobal.viewport_pos.y + viewport_height > PersistGlobal.buffer.height) {
        PersistGlobal.viewport_pos.y = PersistGlobal.buffer.height - viewport_height;
    }
    PersistGlobal.viewport = ViewPort{
        .camera_transform = CoordinateTransform{
            .translate_x = 50.0,
            .translate_y = -20.0,
            .scale = 1.5,
        },
        .buffer = PersistGlobal.buffer.subBuffer(
            viewport_width,
            viewport_height,
            PersistGlobal.viewport_pos,
        ) catch unreachable,
    };
}

fn resize(pixels: []u32, width: ScreenCoordinate, height: ScreenCoordinate) void {
    PersistGlobal.buffer = PixelBuffer.init(pixels, width, height) catch unreachable;
    updateViewPort();
}

fn processInput(input: *const InputState) void {
    if (input.key_space_down) {
        PersistGlobal.viewport_pos.x += 5;
        PersistGlobal.viewport_pos.y += 5;
        updateViewPort();
    }
    if (input.mouse_right_down) {
        PersistGlobal.scene.current_polygon = PersistGlobal.scene.addPolygon() catch unreachable;
    }
    const pointer = PointInt{
        .x = input.mouse_x,
        .y = input.mouse_y,
    };
    const pointer_scene = PersistGlobal.viewport.camera_transform.reverseInt(
        &pointer.sub(&PointInt.fromPixel(&PersistGlobal.viewport_pos)),
    );
    var poly = PersistGlobal.scene.current_polygon;
    if (input.mouse_left_down) {
        if (poly.n == 0) {
            poly.add_vertex(pointer_scene) catch unreachable;
        }
        poly.add_vertex(pointer_scene) catch unreachable;
    }
    if (input.mouse_middle_down) {
        if (PersistGlobal.scene.obj != null) {
            PersistGlobal.scene.obj.?.circle.c = pointer_scene;
        }
    }
    if (poly.n > 0) {
        poly.first.prev.p.x = pointer_scene.x;
        poly.first.prev.p.y = pointer_scene.y;
    }

    const factor_a = (@as(f64, @floatFromInt(input.controller_left_y)) + 32768) / 32768;
    const factor_b = (@as(f64, @floatFromInt(input.controller_right_y)) + 32768) / 32768;
    PersistGlobal.tone_a = TONE_A * factor_a;
    PersistGlobal.tone_b = TONE_B * factor_b;
    // std.debug.print("{d}\t{d}\n", .{ input.controller_left_x, input.controller_left_y });
}

fn writeAudio(buffer: *ApplicationAudioBuffer) void {
    const Persist = struct {
        var phase_a: f64 = 0.0;
        var phase_b: f64 = 0.0;
    };

    const period_a = @as(f32, @floatFromInt(AudioSettings.sample_rate)) / PersistGlobal.tone_a;
    const period_b = @as(f32, @floatFromInt(AudioSettings.sample_rate)) / PersistGlobal.tone_b;
    const two_pi = 2 * std.math.pi;

    const frame_count = buffer.sample_count / AudioSettings.channel_count;

    var i: u32 = 0;
    while (i < frame_count) {
        const amplitude_a = std.math.sin(Persist.phase_a) * PersistGlobal.tone_vol;
        const amplitude_b = std.math.sin(Persist.phase_b) * PersistGlobal.tone_vol;
        const sample_value = @as(i16, @intFromFloat(amplitude_a + amplitude_b));
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
