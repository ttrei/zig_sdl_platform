pub usingnamespace @cImport({
    @cDefine("GLEW_NO_GLU", "");
    @cInclude("GL/glew.h");

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cDefine("CIMGUI_USE_SDL2", "");
    @cDefine("CIMGUI_USE_OPENGL3", "");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");

    // TODO: Was this necessary for windows build?
    // @cDefine("GL_GLEXT_PROTOTYPES", "");
    // @cInclude("SDL_opengl.h");
});
