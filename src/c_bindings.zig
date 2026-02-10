// Minimal c_bindings.zig - extracted from the full cimgui/GL/GLEW/SDL2 translation.
// Only contains symbols actually used by sdl_platform.zig and example.zig.

// =============================================================================
// GL type aliases
// =============================================================================

pub const GLenum = c_uint;
pub const GLuint = c_uint;
pub const GLint = c_int;
pub const GLsizei = c_int;
pub const GLboolean = u8;
pub const GLubyte = u8;
pub const GLchar = u8;
pub const ptrdiff_t = c_long;
pub const GLsizeiptr = ptrdiff_t;

// =============================================================================
// ImGui opaque types (only used via pointers)
// =============================================================================

pub const struct_ImGuiContext = extern struct { _: u8 = 0 };
pub const ImGuiContext = struct_ImGuiContext;

pub const struct_ImDrawData = extern struct { _: u8 = 0 };
pub const ImDrawData = struct_ImDrawData;

pub const struct_ImFontAtlas = extern struct { _: u8 = 0 };
pub const ImFontAtlas = struct_ImFontAtlas;

pub const ImGuiSliderFlags = c_int;

// =============================================================================
// SDL opaque types (forward declarations, only used via pointers)
// =============================================================================

pub const struct_SDL_Window = opaque {};
pub const SDL_Window = struct_SDL_Window;

pub const union_SDL_Event = opaque {};
pub const SDL_Event = union_SDL_Event;

// =============================================================================
// GL constants
// =============================================================================

pub const GL_FALSE = @as(c_int, 0);
pub const GL_TRIANGLES = @as(c_int, 0x0004);
pub const GL_FRONT_AND_BACK = @as(c_int, 0x0408);
pub const GL_UNSIGNED_INT = @as(c_int, 0x1405);
pub const GL_FLOAT = @as(c_int, 0x1406);
pub const GL_RGB = @as(c_int, 0x1907);
pub const GL_RGBA = @as(c_int, 0x1908);
pub const GL_LINE = @as(c_int, 0x1B01);
pub const GL_NEAREST = @as(c_int, 0x2600);
pub const GL_TEXTURE_MAG_FILTER = @as(c_int, 0x2800);
pub const GL_TEXTURE_MIN_FILTER = @as(c_int, 0x2801);
pub const GL_TEXTURE_2D = @as(c_int, 0x0DE1);
pub const GL_UNSIGNED_INT_8_8_8_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8035, .hex);
pub const GL_TEXTURE0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x84C0, .hex);
pub const GL_ARRAY_BUFFER = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8892, .hex);
pub const GL_ELEMENT_ARRAY_BUFFER = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8893, .hex);
pub const GL_STATIC_DRAW = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x88E4, .hex);
pub const GL_FRAGMENT_SHADER = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8B30, .hex);
pub const GL_VERTEX_SHADER = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8B31, .hex);
pub const GL_COMPILE_STATUS = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8B81, .hex);
pub const GL_LINK_STATUS = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8B82, .hex);
pub const GLEW_OK = @as(c_int, 0);

// =============================================================================
// GLEW function pointer types (PFNGL*PROC)
// =============================================================================

pub const PFNGLACTIVETEXTUREPROC = ?*const fn (GLenum) callconv(.c) void;
pub const PFNGLATTACHSHADERPROC = ?*const fn (GLuint, GLuint) callconv(.c) void;
pub const PFNGLBINDBUFFERPROC = ?*const fn (GLenum, GLuint) callconv(.c) void;
pub const PFNGLBUFFERDATAPROC = ?*const fn (GLenum, GLsizeiptr, ?*const anyopaque, GLenum) callconv(.c) void;
pub const PFNGLDELETEBUFFERSPROC = ?*const fn (GLsizei, [*c]const GLuint) callconv(.c) void;
pub const PFNGLGENBUFFERSPROC = ?*const fn (GLsizei, [*c]GLuint) callconv(.c) void;
pub const PFNGLCOMPILESHADERPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLCREATEPROGRAMPROC = ?*const fn () callconv(.c) GLuint;
pub const PFNGLCREATESHADERPROC = ?*const fn (GLenum) callconv(.c) GLuint;
pub const PFNGLDELETEPROGRAMPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLDELETESHADERPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLENABLEVERTEXATTRIBARRAYPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLGETPROGRAMIVPROC = ?*const fn (GLuint, GLenum, [*c]GLint) callconv(.c) void;
pub const PFNGLGETSHADERIVPROC = ?*const fn (GLuint, GLenum, [*c]GLint) callconv(.c) void;
pub const PFNGLGETUNIFORMLOCATIONPROC = ?*const fn (GLuint, [*c]const GLchar) callconv(.c) GLint;
pub const PFNGLLINKPROGRAMPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLSHADERSOURCEPROC = ?*const fn (GLuint, GLsizei, [*c]const [*c]const GLchar, [*c]const GLint) callconv(.c) void;
pub const PFNGLUNIFORM1IPROC = ?*const fn (GLint, GLint) callconv(.c) void;
pub const PFNGLUSEPROGRAMPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLVERTEXATTRIBPOINTERPROC = ?*const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.c) void;
pub const PFNGLBINDVERTEXARRAYPROC = ?*const fn (GLuint) callconv(.c) void;
pub const PFNGLDELETEVERTEXARRAYSPROC = ?*const fn (GLsizei, [*c]const GLuint) callconv(.c) void;
pub const PFNGLGENVERTEXARRAYSPROC = ?*const fn (GLsizei, [*c]GLuint) callconv(.c) void;

// =============================================================================
// GLEW extern global function pointers
// =============================================================================

pub extern var __glewActiveTexture: PFNGLACTIVETEXTUREPROC;
pub extern var __glewAttachShader: PFNGLATTACHSHADERPROC;
pub extern var __glewBindBuffer: PFNGLBINDBUFFERPROC;
pub extern var __glewBufferData: PFNGLBUFFERDATAPROC;
pub extern var __glewCompileShader: PFNGLCOMPILESHADERPROC;
pub extern var __glewCreateProgram: PFNGLCREATEPROGRAMPROC;
pub extern var __glewCreateShader: PFNGLCREATESHADERPROC;
pub extern var __glewDeleteBuffers: PFNGLDELETEBUFFERSPROC;
pub extern var __glewDeleteProgram: PFNGLDELETEPROGRAMPROC;
pub extern var __glewDeleteShader: PFNGLDELETESHADERPROC;
pub extern var __glewDeleteVertexArrays: PFNGLDELETEVERTEXARRAYSPROC;
pub extern var __glewEnableVertexAttribArray: PFNGLENABLEVERTEXATTRIBARRAYPROC;
pub extern var __glewGenBuffers: PFNGLGENBUFFERSPROC;
pub extern var __glewGenVertexArrays: PFNGLGENVERTEXARRAYSPROC;
pub extern var __glewGetProgramiv: PFNGLGETPROGRAMIVPROC;
pub extern var __glewGetShaderiv: PFNGLGETSHADERIVPROC;
pub extern var __glewGetUniformLocation: PFNGLGETUNIFORMLOCATIONPROC;
pub extern var __glewLinkProgram: PFNGLLINKPROGRAMPROC;
pub extern var __glewShaderSource: PFNGLSHADERSOURCEPROC;
pub extern var __glewUniform1i: PFNGLUNIFORM1IPROC;
pub extern var __glewUseProgram: PFNGLUSEPROGRAMPROC;
pub extern var __glewVertexAttribPointer: PFNGLVERTEXATTRIBPOINTERPROC;
pub extern var __glewBindVertexArray: PFNGLBINDVERTEXARRAYPROC;

// =============================================================================
// GL extern functions (from libGL)
// =============================================================================

pub extern fn glBindTexture(target: GLenum, texture: GLuint) void;
pub extern fn glDeleteTextures(n: GLsizei, textures: [*c]const GLuint) void;
pub extern fn glDrawElements(mode: GLenum, count: GLsizei, @"type": GLenum, indices: ?*const anyopaque) void;
pub extern fn glGenTextures(n: GLsizei, textures: [*c]GLuint) void;
pub extern fn glTexImage2D(target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, @"type": GLenum, pixels: ?*const anyopaque) void;
pub extern fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) void;
pub extern fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) void;

// =============================================================================
// GLEW extern functions
// =============================================================================

pub extern fn glewInit() GLenum;
pub extern fn glewGetErrorString(@"error": GLenum) [*c]const GLubyte;

// =============================================================================
// ImGui extern functions
// =============================================================================

pub extern fn igCreateContext(shared_font_atlas: [*c]ImFontAtlas) [*c]ImGuiContext;
pub extern fn igDestroyContext(ctx: [*c]ImGuiContext) void;
pub extern fn igGetDrawData() [*c]ImDrawData;
pub extern fn igNewFrame() void;
pub extern fn igRender() void;
pub extern fn igText(fmt: [*c]const u8, ...) void;
pub extern fn igSliderFloat(label: [*c]const u8, v: [*c]f32, v_min: f32, v_max: f32, format: [*c]const u8, flags: ImGuiSliderFlags) bool;
pub extern fn igShowDemoWindow(p_open: [*c]bool) void;

// =============================================================================
// ImGui backend extern functions
// =============================================================================

pub extern fn ImGui_ImplOpenGL3_Init(glsl_version: [*c]const u8) bool;
pub extern fn ImGui_ImplOpenGL3_Shutdown() void;
pub extern fn ImGui_ImplOpenGL3_NewFrame() void;
pub extern fn ImGui_ImplOpenGL3_RenderDrawData(draw_data: [*c]ImDrawData) void;
pub extern fn ImGui_ImplSDL2_InitForOpenGL(window: ?*SDL_Window, sdl_gl_context: ?*anyopaque) bool;
pub extern fn ImGui_ImplSDL2_Shutdown() void;
pub extern fn ImGui_ImplSDL2_NewFrame() void;
pub extern fn ImGui_ImplSDL2_ProcessEvent(event: ?*const SDL_Event) bool;
