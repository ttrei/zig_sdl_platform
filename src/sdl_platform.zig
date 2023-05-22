const std = @import("std");
const SDL = @import("sdl2");
pub const c = @import("c.zig");

const Allocator = std.mem.Allocator;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpa_allocator = gpa.allocator();

const ScreenBuffer = @import("handmade_gl").ScreenBuffer;

const MAGENTA = 0xFF00FFFF;

// Platform providing the core loop and a display using SDL+OpenGL+ImGui.

// SDL is already a cross-platform library but defining an interface between
// platform and application code is still probably worthwile.

pub fn coreLoop(
    updateCallback: *const fn (f64) void,
    renderCallback: *const fn (*ScreenBuffer) void,
    resizeCallback: *const fn (u32, u32) void,
    inputCallback: *const fn (*const InputState) void,
) !void {
    const WINDOW_WIDTH = 1000;
    const WINDOW_HEIGHT = 600;
    const TARGET_FPS = 60;
    const SIMULATION_UPS = 100;

    const step = @intToFloat(f64, 1) / SIMULATION_UPS;
    const ns_per_update = std.time.ns_per_s / SIMULATION_UPS;

    var platform = SdlPlatform{};
    try platform.init(gpa_allocator, "Handmade Pool", WINDOW_WIDTH, WINDOW_HEIGHT);
    defer platform.deinit();

    resizeCallback(WINDOW_WIDTH, WINDOW_HEIGHT);

    var show_demo_window: bool = false;

    var current_time: i128 = std.time.nanoTimestamp();
    var previous_time: i128 = undefined;
    var game_accumulator: i128 = 0;
    var fps_accumulator: i128 = 0;
    var fps_frame_count: usize = 0;
    var fps: f32 = 0;

    var input = InputState{};

    var raw_event: SDL.c.SDL_Event = undefined;
    the_loop: while (true) {
        input.reset();

        while (SDL.c.SDL_PollEvent(&raw_event) != 0) {
            _ = c.ImGui_ImplSDL2_ProcessEvent(@ptrCast(*const c.union_SDL_Event, &raw_event));
            const event = SDL.Event.from(raw_event);
            switch (event) {
                .quit => break :the_loop,
                .key_down => |ev| {
                    switch (ev.keycode) {
                        .escape => break :the_loop,
                        .space => input.key_space_down = true,
                        .s => input.key_s_down = true,
                        else => {},
                    }
                },
                .mouse_motion => |ev| {
                    input.mouse_x = ev.x;
                    input.mouse_y = ev.y;
                    input.mouse_dx = ev.delta_x;
                    input.mouse_dy = ev.delta_y;
                },
                .mouse_button_down => |ev| {
                    switch (ev.button) {
                        .left => input.mouse_left_down = true,
                        .right => input.mouse_right_down = true,
                        else => {},
                    }
                },
                .window => |ev| {
                    switch (ev.type) {
                        .resized => |resize_event| {
                            const width = @intCast(u32, resize_event.width);
                            const height = @intCast(u32, resize_event.height);
                            try platform.resize(gpa_allocator, width, height);
                            resizeCallback(width, height);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        inputCallback(&input);

        while (game_accumulator >= ns_per_update) : (game_accumulator -= ns_per_update) {
            updateCallback(step);
        }

        platform.new_imgui_frame();
        if (show_demo_window) c.igShowDemoWindow(&show_demo_window);

        imguiText("FPS: {d:.2}", .{fps});

        renderCallback(&platform.screen_buffer);
        platform.render();

        // update FPS twice per second
        if (fps_frame_count > TARGET_FPS / 2) {
            fps = @intToFloat(f32, fps_frame_count) * std.time.ns_per_s / @intToFloat(f32, fps_accumulator);
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

    key_space_down: bool = false,
    key_s_down: bool = false,

    fn reset(self: *InputState) void {
        self.mouse_dx = 0;
        self.mouse_dy = 0;
        self.mouse_left_down = false;
        self.mouse_right_down = false;
        self.key_space_down = false;
        self.key_s_down = false;
    }
};

pub const SdlPlatform = struct {
    window: SDL.Window = undefined,
    imgui_context: [*c]c.ImGuiContext = undefined,
    screen_buffer: ScreenBuffer = undefined,

    // OpenGL stuff necessary to draw a full-screen quad
    gl_context: SDL.gl.Context = undefined,
    vao: c_uint = undefined,
    vbo: c_uint = undefined,
    ebo: c_uint = undefined,
    texture: c_uint = undefined,
    shader_program: c_uint = undefined,
    const vertices = [_]f32{
        // 3 vertex coordinates, 2 texture coordinates
        // The texture coordinate y-components are inverted to account for the
        // different y-axis directions between ScreenBuffer and OpenGL.
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
        allocator: Allocator,
        window_name: [:0]const u8,
        comptime width: comptime_int,
        comptime height: comptime_int,
    ) !void {
        try SDL.init(.{
            .video = true,
            .audio = false,
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
        try SDL.gl.makeCurrent(self.gl_context, self.window);
        // try SDL.gl.setSwapInterval(.vsync);

        self.imgui_context = c.igCreateContext(null);
        if (!c.ImGui_ImplSDL2_InitForOpenGL(
            @ptrCast(*c.struct_SDL_Window, self.window.ptr),
            &self.gl_context,
        )) return error.ImGuiSDL2ForOpenGLInitFailed;
        if (!c.ImGui_ImplOpenGL3_Init(glsl_version)) return error.ImGuiOpenGL3InitFailed;

        self.initOpenGLObjects();
        try self.createScreenBufferAndTexture(allocator, width, height);
        c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    }

    pub fn deinit(self: *SdlPlatform) void {
        self.deinitOpenGLObjects();
        self.screen_buffer.deinit();
        c.ImGui_ImplOpenGL3_Shutdown();
        c.ImGui_ImplSDL2_Shutdown();
        c.igDestroyContext(self.imgui_context);
        SDL.gl.deleteContext(self.gl_context);
        self.window.destroy();
        SDL.quit();
    }

    pub fn resize(self: *SdlPlatform, allocator: Allocator, width: u32, height: u32) !void {
        c.glDeleteTextures(1, &self.texture);
        self.screen_buffer.deinit();
        try self.createScreenBufferAndTexture(allocator, width, height);
        c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    }

    pub fn new_imgui_frame(self: *SdlPlatform) void {
        _ = self;
        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplSDL2_NewFrame();
        c.igNewFrame();
    }

    pub fn render(self: *SdlPlatform) void {
        c.glClearColor(1.0, 0.0, 0.0, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        self.blitScreenBuffer();
        self.screen_buffer.clear(MAGENTA);

        c.glUseProgram(self.shader_program);
        c.glBindVertexArray(self.vao);
        // Draw the full-screen quad
        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, @intToPtr(*allowzero anyopaque, 0));

        // ImGui
        c.igRender();
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());

        SDL.gl.swapWindow(self.window);
    }

    fn initOpenGLObjects(self: *SdlPlatform) void {
        // Followed https://learnopengl.com/Getting-started/Hello-Triangle.
        // Gained enough understanding to create a full-screen quad with a
        // texture containing the screen buffer.
        c.glGenVertexArrays(1, &self.vao);
        c.glBindVertexArray(self.vao);

        c.glGenBuffers(1, &self.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, c.GL_STATIC_DRAW);
        // vertex attribute for coordinates
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @intToPtr(*allowzero anyopaque, 0));
        c.glEnableVertexAttribArray(0);
        // vertex attribute for texture coordinates
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @intToPtr(*anyopaque, 3 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(1);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        c.glGenBuffers(1, &self.ebo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * indices.len, &indices, c.GL_STATIC_DRAW);

        c.glBindVertexArray(0);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);

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
        const vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
        defer c.glDeleteShader(vertex_shader);
        c.glShaderSource(vertex_shader, 1, &@ptrCast([*c]const u8, vertex_shader_source), null);
        c.glCompileShader(vertex_shader);
        c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &success);
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
        const frag_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        defer c.glDeleteShader(frag_shader);
        c.glShaderSource(frag_shader, 1, &@ptrCast([*c]const u8, frag_shader_source), null);
        c.glCompileShader(frag_shader);
        c.glGetShaderiv(frag_shader, c.GL_COMPILE_STATUS, &success);
        // std.debug.print("fragment shader compilation status = {}\n", .{success});

        self.shader_program = c.glCreateProgram();
        c.glAttachShader(self.shader_program, vertex_shader);
        c.glAttachShader(self.shader_program, frag_shader);
        c.glLinkProgram(self.shader_program);
        c.glGetProgramiv(self.shader_program, c.GL_LINK_STATUS, &success);
        // std.debug.print("shader program link status = {}\n", .{success});

        // Wireframe mode
        // c.glPolygonMode(c.GL_FRONT_AND_BACK, c.GL_LINE);
    }

    fn deinitOpenGLObjects(self: *SdlPlatform) void {
        c.glDeleteTextures(1, &self.texture);
        c.glDeleteProgram(self.shader_program);
        c.glDeleteBuffers(1, &self.ebo);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteVertexArrays(1, &self.vao);
    }

    fn createScreenBufferAndTexture(self: *SdlPlatform, allocator: Allocator, width: u32, height: u32) !void {
        self.screen_buffer = try ScreenBuffer.init(allocator, width, height);
        self.screen_buffer.clear(MAGENTA);

        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glUseProgram(self.shader_program);
        c.glUniform1i(c.glGetUniformLocation(self.shader_program, "screenBuffer"), 0);

        self.blitScreenBuffer();
    }

    fn blitScreenBuffer(self: *SdlPlatform) void {
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        // Transfer screen_buffer to the texture
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGB,
            @intCast(c_int, self.screen_buffer.width),
            @intCast(c_int, self.screen_buffer.height),
            0,
            c.GL_RGBA,
            // Had problems with endianness of the color bytes.
            // Fixed by using GL_UNSIGNED_INT_8_8_8_8 - https://stackoverflow.com/a/6637317/9124671.
            // I don't have a deep understanding of what's going on here, but that's OK.
            // This code needs to be just good enough to transfer screen buffer to the quad.
            c.GL_UNSIGNED_INT_8_8_8_8,
            self.screen_buffer.pixels.ptr,
        );
    }
};