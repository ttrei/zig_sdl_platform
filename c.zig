pub usingnamespace @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");

    @cDefine("GL_GLEXT_PROTOTYPES", "");
    @cInclude("SDL_opengl.h");
});
