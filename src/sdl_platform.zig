const std = @import("std");
const SDL = @import("sdl2");
pub const c = @import("c.zig");

const Allocator = std.mem.Allocator;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

pub const AudioSettings = struct {
    pub const sample_type = i16;
    pub const buffer_format = SDL.AudioFormat.s16_lsb;
    pub const sample_rate = 48_000;
    // A frame consists of channel_count number of samples.
    // "sample_rate" actually means "frame rate".
    pub const channel_count = 2;
    // Number of samples that we will ask the application to write.
    // It must be larger than the number of samples requested by SDL callback.
    pub const latency_sample_count = (sample_rate / 10) * channel_count;
    pub const bytes_per_frame = @sizeOf(sample_type) * channel_count;
    // Our buffers will contain 1 second of samples
    pub const buffer_size_in_samples = sample_rate * channel_count;
};

const MAGENTA = 0xFF00FFFF;

const Global = struct {
    var screen_width: u32 = undefined;
    var screen_height: u32 = undefined;
};

pub const ApplicationAudioBuffer = struct {
    // Linear buffer to transfer audio from application to platform
    // Application audio callback writes sample_count samples to the beginning of the buffer.
    samples: []AudioSettings.sample_type,
    sample_count: u32,
    const Self = @This();

    fn init() !Self {
        const buffer = Self{
            .samples = try gpa_allocator.alloc(
                AudioSettings.sample_type,
                AudioSettings.buffer_size_in_samples,
            ),
            .sample_count = 0,
        };
        // Initialize to silence
        for (buffer.samples) |*sample| {
            sample.* = 0;
        }
        return buffer;
    }
    fn deinit(self: *const Self) void {
        gpa_allocator.free(self.samples);
    }
};

const SdlAudioRingBuffer = struct {
    samples: []AudioSettings.sample_type,
    write_cursor: u32, // next sample to be written
    play_cursor: u32, // next sample to be played
    const Self = @This();

    pub fn init() !Self {
        return Self{
            .samples = try gpa_allocator.alloc(
                AudioSettings.sample_type,
                AudioSettings.buffer_size_in_samples,
            ),
            .write_cursor = 0,
            .play_cursor = 0,
        };
    }
    pub fn deinit(self: *const Self) void {
        gpa_allocator.free(self.samples);
    }

    pub fn copyAudio(self: *Self, buffer: *const ApplicationAudioBuffer) void {
        if (buffer.sample_count == 0) {
            return;
        }
        if (self.write_cursor + buffer.sample_count < self.samples.len) {
            const source = buffer.samples[0..buffer.sample_count];
            const target = self.samples[self.write_cursor .. self.write_cursor + buffer.sample_count];
            @memcpy(target, source);
            self.write_cursor += buffer.sample_count;
        } else {
            // wrap-around
            const region1_size: u32 = @intCast(self.samples.len - self.write_cursor);
            const region2_size: u32 = @intCast(buffer.sample_count - region1_size);
            var source = buffer.samples[0..region1_size];
            var target = self.samples[self.write_cursor..];
            @memcpy(target, source);
            source = buffer.samples[region1_size..buffer.sample_count];
            target = self.samples[0..region2_size];
            @memcpy(target, source);
            self.write_cursor = region2_size;
        }
    }
};

fn sdlAudioCallback(userdata: ?*anyopaque, audio_data: [*c]u8, length_in_bytes_c: c_int) callconv(.C) void {
    const audio_buffer: *SdlAudioRingBuffer = @ptrCast(@alignCast(userdata));

    const length_in_bytes: u32 = @intCast(length_in_bytes_c);
    const bytes_per_sample = @sizeOf(AudioSettings.sample_type);
    const buffer_size_in_bytes = bytes_per_sample * audio_buffer.samples.len;

    if (audio_buffer.play_cursor * bytes_per_sample + length_in_bytes < buffer_size_in_bytes) {
        const source = @as([*]u8, @ptrCast(audio_buffer.samples.ptr)) + audio_buffer.play_cursor * bytes_per_sample;
        var i: usize = 0;
        while (i < length_in_bytes) {
            audio_data[i] = source[i];
            i += 1;
        }
    } else {
        // wrap-around
        const region1_size = buffer_size_in_bytes - audio_buffer.play_cursor * bytes_per_sample;
        const region2_size = length_in_bytes - region1_size;
        var source = @as([*]u8, @ptrCast(audio_buffer.samples.ptr)) + audio_buffer.play_cursor * bytes_per_sample;
        var i: usize = 0;
        while (i < region1_size) {
            audio_data[i] = source[i];
            i += 1;
        }
        source = @as([*]u8, @ptrCast(audio_buffer.samples.ptr));
        i = 0;
        while (i < region2_size) {
            audio_data[region1_size + i] = source[i];
            i += 1;
        }
    }

    const samples_played = length_in_bytes / bytes_per_sample;
    audio_buffer.play_cursor += samples_played;
    audio_buffer.play_cursor %= @intCast(audio_buffer.samples.len);
}

fn initSdlAudioDevice(audio_buffer: *SdlAudioRingBuffer) !SDL.AudioDevice {
    const result = try SDL.openAudioDevice(.{ .desired_spec = .{
        .sample_rate = AudioSettings.sample_rate,
        .buffer_format = AudioSettings.buffer_format,
        .channel_count = AudioSettings.channel_count,
        .callback = sdlAudioCallback,
        .userdata = @ptrCast(audio_buffer),
    } });
    return result.device;
}

pub fn coreLoop(
    updateCallback: *const fn (f64) void,
    renderCallback: *const fn () void,
    resizeCallback: *const fn ([]u32, u32, u32) void,
    inputCallback: *const fn (*const InputState) void,
    audioCallback: *const fn (*ApplicationAudioBuffer) void,
) !void {
    const WINDOW_WIDTH = 1000;
    const WINDOW_HEIGHT = 600;
    const SIMULATION_UPS = 100;

    const step = 1.0 / @as(comptime_float, SIMULATION_UPS);
    const ns_per_update = std.time.ns_per_s / SIMULATION_UPS;

    var platform = SdlPlatform{};
    try platform.init("Handmade Pool", WINDOW_WIDTH, WINDOW_HEIGHT);
    defer platform.deinit();

    try platform.resize(WINDOW_WIDTH, WINDOW_HEIGHT);
    resizeCallback(platform.screen_buffer, WINDOW_WIDTH, WINDOW_HEIGHT);

    var show_demo_window: bool = false;

    var current_time: i128 = std.time.nanoTimestamp();
    var previous_time: i128 = undefined;
    var game_accumulator: i128 = 0;
    var fps_accumulator: i128 = 0;
    var fps_frame_count: usize = 0;
    var fps: f32 = 0;

    var input = InputState{};

    if (try SDL.numJoysticks() > 0) {
        _ = try SDL.GameController.open(0);
    }

    var application_audio_buffer = try ApplicationAudioBuffer.init();
    defer application_audio_buffer.deinit();

    var raw_event: SDL.c.SDL_Event = undefined;
    the_loop: while (true) {
        input.reset();

        while (SDL.c.SDL_PollEvent(&raw_event) != 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(@ptrCast(&raw_event));
            const event = SDL.Event.from(raw_event);
            switch (event) {
                .quit => break :the_loop,
                .key_down => |ev| {
                    switch (ev.keycode) {
                        .escape => break :the_loop,
                        .space => input.key_space_down = true,
                        .backspace => input.key_backspace_down = true,
                        .s => input.key_s_down = true,
                        else => {},
                    }
                },
                .mouse_motion => |ev| {
                    input.mouse_x = ev.x;
                    input.mouse_y = ev.y;
                    input.mouse_dx += ev.delta_x;
                    input.mouse_dy += ev.delta_y;
                },
                .mouse_button_down => |ev| {
                    switch (ev.button) {
                        .left => input.mouse_left_down = true,
                        .right => input.mouse_right_down = true,
                        .middle => input.mouse_middle_down = true,
                        else => {},
                    }
                },
                .mouse_wheel => |ev| {
                    input.mouse_wheel_dx += ev.delta_x;
                    input.mouse_wheel_dy += ev.delta_y;
                },
                .mouse_button_up => |ev| {
                    switch (ev.button) {
                        .left => input.mouse_left_up = true,
                        .right => input.mouse_right_up = true,
                        .middle => input.mouse_middle_up = true,
                        else => {},
                    }
                },
                .controller_axis_motion => |ev| {
                    switch (ev.axis) {
                        .left_x => input.controller_left_x = ev.value,
                        .left_y => input.controller_left_y = ev.value,
                        .right_x => input.controller_right_x = ev.value,
                        .right_y => input.controller_right_y = ev.value,
                        else => {},
                    }
                },
                .window => |ev| {
                    switch (ev.type) {
                        .resized => |resize_event| {
                            const width: u32 = @intCast(resize_event.width);
                            const height: u32 = @intCast(resize_event.height);
                            try platform.resize(width, height);
                            resizeCallback(platform.screen_buffer, width, height);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        inputCallback(&input);

        var i: usize = 0;
        update_loop: while (game_accumulator >= ns_per_update) : ({
            game_accumulator -= ns_per_update;
            i += 1;
        }) {
            updateCallback(step);
            if (i > 100) {
                std.debug.print("WARNING! Physics updated 100 times in one frame\n", .{});
                game_accumulator = 0;
                break :update_loop;
            }
        }

        platform.process_audio(&application_audio_buffer, audioCallback);

        platform.new_imgui_frame();
        if (show_demo_window) c.igShowDemoWindow(&show_demo_window);

        imguiText("FPS: {d:.2}", .{fps});

        renderCallback();
        platform.render();

        // update FPS twice per second
        if (fps_accumulator > std.time.ns_per_s / 2) {
            fps = @as(f32, @floatFromInt(fps_frame_count * std.time.ns_per_s)) / @as(f32, @floatFromInt(fps_accumulator));
            fps_accumulator = 0;
            fps_frame_count = 0;
        }
        previous_time = current_time;
        current_time = std.time.nanoTimestamp();
        game_accumulator += current_time - previous_time;
        fps_accumulator += current_time - previous_time;
        fps_frame_count += 1;
    }
}

pub fn imguiText(comptime fmt: []const u8, args: anytype) void {
    // I'm doing this bufPrintZ() dance because igText() fails to format a
    // float - it always outputs 0.00.  Traced the problem to vsnprintf() in
    // imgui.cpp::ImFormatString().
    // Maybe my libc was somehow compiled without float formatting support?
    // Didn't investigate further.
    // Also tried to switch to stb_sprintf.h by defining
    // IMGUI_USE_STB_SPRINTF, but it crashed with segmentation fault.
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, fmt, args) catch unreachable;
    c.igText("%s", text.ptr);
}

pub const InputState = struct {
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_dx: i32 = 0,
    mouse_dy: i32 = 0,

    mouse_left_down: bool = false,
    mouse_right_down: bool = false,
    mouse_middle_down: bool = false,
    mouse_left_up: bool = false,
    mouse_right_up: bool = false,
    mouse_middle_up: bool = false,

    mouse_wheel_dx: i32 = 0,
    mouse_wheel_dy: i32 = 0,

    controller_left_x: i16 = 0,
    controller_left_y: i16 = 0,
    controller_right_x: i16 = 0,
    controller_right_y: i16 = 0,

    key_space_down: bool = false,
    key_backspace_down: bool = false,
    key_s_down: bool = false,

    fn reset(self: *InputState) void {
        self.mouse_dx = 0;
        self.mouse_dy = 0;
        self.mouse_left_down = false;
        self.mouse_right_down = false;
        self.mouse_middle_down = false;
        self.mouse_left_up = false;
        self.mouse_right_up = false;
        self.mouse_middle_up = false;
        self.mouse_wheel_dx = 0;
        self.mouse_wheel_dy = 0;
        self.key_space_down = false;
        self.key_backspace_down = false;
        self.key_s_down = false;
    }
};

pub const SdlPlatform = struct {
    window: SDL.Window = undefined,
    imgui_context: [*c]c.ImGuiContext = undefined,
    screen_buffer: []u32 = undefined,

    // OpenGL stuff necessary to draw a full-screen quad
    gl_context: SDL.gl.Context = undefined,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,
    texture: c_uint = undefined,
    shader_program: c_uint = undefined,

    audio_buffer: SdlAudioRingBuffer = undefined,
    audio_device: SDL.AudioDevice = undefined,

    const vertices = [_]f32{
        // 3 vertex coordinates, 2 texture coordinates
        // The texture coordinate y-components are inverted to account for the
        // different y-axis directions between screen buffer and OpenGL.
        1.0, 1.0, 0.0, 1.0, 0.0, // top right vertex
        1.0, -1.0, 0.0, 1.0, 1.0, // bottom right vertex
        -1.0, -1.0, 0.0, 0.0, 1.0, // bottom left vertex
        -1.0, 1.0, 0.0, 0.0, 0.0, // top left vertex
    };
    const indices = [_]u32{
        0, 1, 3, // first triangle
        1, 2, 3, // second triangle
    };

    pub fn init(
        self: *SdlPlatform,
        window_name: [:0]const u8,
        comptime width: comptime_int,
        comptime height: comptime_int,
    ) !void {
        try SDL.init(.{
            .video = true,
            .audio = true,
            .game_controller = true,
            .timer = true,
        });

        const glsl_version = "#version 130";
        try SDL.gl.setAttribute(.{ .context_flags = .{} });
        try SDL.gl.setAttribute(.{ .context_profile_mask = .core });
        try SDL.gl.setAttribute(.{ .context_major_version = 3 });
        try SDL.gl.setAttribute(.{ .context_minor_version = 0 });

        try SDL.gl.setAttribute(.{ .doublebuffer = true });
        try SDL.gl.setAttribute(.{ .depth_size = 24 });
        try SDL.gl.setAttribute(.{ .stencil_size = 8 });

        self.window = try SDL.createWindow(
            window_name,
            .{ .centered = {} },
            .{ .centered = {} },
            width,
            height,
            .{ .vis = .shown, .context = .opengl, .resizable = false, .allow_high_dpi = true },
        );
        self.gl_context = try SDL.gl.createContext(self.window);
        const glew_err = c.glewInit();
        if (glew_err != c.GLEW_OK) {
            const str = @as([*:0]const u8, c.glewGetErrorString(glew_err));
            @panic(std.mem.sliceTo(str, 0));
        }
        try SDL.gl.makeCurrent(self.gl_context, self.window);
        // try SDL.gl.setSwapInterval(.immediate);
        SDL.gl.setSwapInterval(.adaptive_vsync) catch {
            try SDL.gl.setSwapInterval(.vsync);
        };

        self.imgui_context = c.igCreateContext(null);
        if (!c.ImGui_ImplSDL2_InitForOpenGL(
            @ptrCast(self.window.ptr),
            &self.gl_context,
        )) return error.ImGuiSDL2ForOpenGLInitFailed;
        if (!c.ImGui_ImplOpenGL3_Init(glsl_version)) return error.ImGuiOpenGL3InitFailed;

        self.initOpenGLObjects();
        Global.screen_width = width;
        Global.screen_height = height;
        try self.createScreenBufferAndTexture();
        c.glViewport(0, 0, @intCast(width), @intCast(height));

        self.audio_buffer = try SdlAudioRingBuffer.init();
        self.audio_device = try initSdlAudioDevice(&self.audio_buffer);
        self.audio_device.pause(false);
    }

    pub fn deinit(self: *SdlPlatform) void {
        self.audio_device.close();
        self.audio_buffer.deinit();

        self.deinitOpenGLObjects();
        gpa_allocator.free(self.screen_buffer);
        c.ImGui_ImplOpenGL3_Shutdown();
        c.ImGui_ImplSDL2_Shutdown();
        c.igDestroyContext(self.imgui_context);
        SDL.gl.deleteContext(self.gl_context);

        self.window.destroy();
        SDL.quit();
    }

    pub fn resize(self: *SdlPlatform, width: u32, height: u32) !void {
        c.glDeleteTextures(1, &self.texture);
        gpa_allocator.free(self.screen_buffer);
        Global.screen_width = width;
        Global.screen_height = height;
        try self.createScreenBufferAndTexture();
        c.glViewport(0, 0, @intCast(width), @intCast(height));
    }

    pub fn new_imgui_frame(self: *SdlPlatform) void {
        _ = self;
        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        c.igNewFrame();
    }

    pub fn render(self: *SdlPlatform) void {
        self.blitScreenBuffer();

        c.__glewUseProgram.?(self.shader_program);
        c.__glewBindVertexArray.?(self.vao);
        // Draw the full-screen quad
        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, @ptrFromInt(0));

        // ImGui
        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());

        SDL.gl.swapWindow(self.window);
    }

    fn initOpenGLObjects(self: *SdlPlatform) void {
        // Followed https://learnopengl.com/Getting-started/Hello-Triangle.
        // Gained enough understanding to create a full-screen quad with a
        // texture containing the screen buffer.
        c.__glewGenVertexArrays.?(1, &self.vao);
        c.__glewBindVertexArray.?(self.vao);

        c.__glewGenBuffers.?(1, &self.vbo);
        c.__glewBindBuffer.?(c.GL_ARRAY_BUFFER, self.vbo);
        c.__glewBufferData.?(c.GL_ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, c.GL_STATIC_DRAW);
        // vertex attribute for coordinates
        c.__glewVertexAttribPointer.?(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
        c.__glewEnableVertexAttribArray.?(0);
        // vertex attribute for texture coordinates
        c.__glewVertexAttribPointer.?(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
        c.__glewEnableVertexAttribArray.?(1);
        c.__glewBindBuffer.?(c.GL_ARRAY_BUFFER, 0);

        c.__glewGenBuffers.?(1, &self.ebo);
        c.__glewBindBuffer.?(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        c.__glewBufferData.?(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * indices.len, &indices, c.GL_STATIC_DRAW);

        c.__glewBindVertexArray.?(0);
        c.__glewBindBuffer.?(c.GL_ELEMENT_ARRAY_BUFFER, 0);

        var success: c_int = undefined;

        const vertex_shader_source =
            \\#version 330 core
            \\layout (location = 0) in vec3 aPos;
            \\layout (location = 1) in vec2 aTexCoord;
            \\
            \\out vec2 TexCoord;
            \\
            \\void main()
            \\{
            \\    gl_Position = vec4(aPos, 1.0);
            \\    TexCoord = aTexCoord;
            \\}
        ;
        const vertex_shader = c.__glewCreateShader.?(c.GL_VERTEX_SHADER);
        defer c.__glewDeleteShader.?(vertex_shader);
        c.__glewShaderSource.?(vertex_shader, 1, @ptrCast(&vertex_shader_source), null);
        c.__glewCompileShader.?(vertex_shader);
        c.__glewGetShaderiv.?(vertex_shader, c.GL_COMPILE_STATUS, &success);
        // std.debug.print("vertex shader compilation status = {}\n", .{success});
        // TODO: learn how to extract the info log in zig
        // if(!success) {
        //     char infoLog[512];
        //     glGetShaderInfoLog(vertexShader, 512, NULL, infoLog);
        //     std::cout << "ERROR::SHADER::VERTEX::COMPILATION_FAILED\n" << infoLog << std::endl;
        // }

        const frag_shader_source =
            \\#version 330 core
            \\out vec4 FragColor;
            \\
            \\in vec2 TexCoord;
            \\
            \\uniform sampler2D screenBuffer;
            \\
            \\void main()
            \\{
            \\    FragColor = texture(screenBuffer, TexCoord);
            \\} 
        ;
        const frag_shader = c.__glewCreateShader.?(c.GL_FRAGMENT_SHADER);
        defer c.__glewDeleteShader.?(frag_shader);
        c.__glewShaderSource.?(frag_shader, 1, @ptrCast(&frag_shader_source), null);
        c.__glewCompileShader.?(frag_shader);
        c.__glewGetShaderiv.?(frag_shader, c.GL_COMPILE_STATUS, &success);
        // std.debug.print("fragment shader compilation status = {}\n", .{success});

        self.shader_program = c.__glewCreateProgram.?();
        c.__glewAttachShader.?(self.shader_program, vertex_shader);
        c.__glewAttachShader.?(self.shader_program, frag_shader);
        c.__glewLinkProgram.?(self.shader_program);
        c.__glewGetProgramiv.?(self.shader_program, c.GL_LINK_STATUS, &success);
        // std.debug.print("shader program link status = {}\n", .{success});

        // Wireframe mode
        // c.__glewPolygonMode.?(c.GL_FRONT_AND_BACK, c.GL_LINE);
    }

    fn deinitOpenGLObjects(self: *SdlPlatform) void {
        c.glDeleteTextures(1, &self.texture);
        c.__glewDeleteProgram.?(self.shader_program);
        c.__glewDeleteBuffers.?(1, &self.ebo);
        c.__glewDeleteBuffers.?(1, &self.vbo);
        c.__glewDeleteVertexArrays.?(1, &self.vao);
    }

    fn createScreenBufferAndTexture(self: *SdlPlatform) !void {
        const num_pixels = Global.screen_width * Global.screen_height;
        self.screen_buffer = try gpa_allocator.alloc(u32, num_pixels);
        for (self.screen_buffer) |*pixel| pixel.* = MAGENTA;

        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.__glewUseProgram.?(self.shader_program);
        c.__glewUniform1i.?(c.__glewGetUniformLocation.?(self.shader_program, "screenBuffer"), 0);

        self.blitScreenBuffer();
    }

    fn blitScreenBuffer(self: *SdlPlatform) void {
        c.__glewActiveTexture.?(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        // Transfer screen_buffer to the texture
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGB,
            @intCast(Global.screen_width),
            @intCast(Global.screen_height),
            0,
            c.GL_RGBA,
            // Had problems with endianness of the color bytes.
            // Fixed by using GL_UNSIGNED_INT_8_8_8_8 - https://stackoverflow.com/a/6637317/9124671.
            // I don't have a deep understanding of what's going on here, but that's OK.
            // This code needs to be just good enough to transfer screen buffer to the quad.
            c.GL_UNSIGNED_INT_8_8_8_8,
            self.screen_buffer.ptr,
        );
    }

    pub fn process_audio(
        self: *SdlPlatform,
        application_buffer: *ApplicationAudioBuffer,
        application_callback: *const fn (*ApplicationAudioBuffer) void,
    ) void {
        const buffer_size: u32 = @intCast(self.audio_buffer.samples.len);
        // Lock to make sure sdlAudioCallback doesn't modify the play_cursor while we are using it
        // for calculations.
        self.audio_device.lock();
        const target_cursor = (self.audio_buffer.play_cursor + AudioSettings.latency_sample_count) % buffer_size;
        self.audio_device.unlock();
        if (self.audio_buffer.write_cursor > target_cursor) {
            application_buffer.sample_count = buffer_size - (self.audio_buffer.write_cursor - target_cursor);
        } else {
            application_buffer.sample_count = target_cursor - self.audio_buffer.write_cursor;
        }
        application_callback(application_buffer);
        self.audio_buffer.copyAudio(application_buffer);
    }
};
