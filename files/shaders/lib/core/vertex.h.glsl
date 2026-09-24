// OPENMW_ANDROID_051_GL4ES_CORE_INLINE
// GL4ES/GLES2 compatibility: keep helper implementations in the consuming
// shader instead of linking a helper-only shader object without main().
uniform mat4 projectionMatrix;

vec4 modelToView(vec4 pos)
{
    return gl_ModelViewMatrix * pos;
}

vec4 modelToClip(vec4 pos)
{
    return projectionMatrix * modelToView(pos);
}

vec4 viewToClip(vec4 pos)
{
    return projectionMatrix * pos;
}
