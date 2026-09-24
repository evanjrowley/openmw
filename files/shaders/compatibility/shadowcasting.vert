#version 120

varying vec2 diffuseMapUV;

varying float alphaPassthrough;

uniform int colorMode;
uniform bool useTreeAnim;
uniform bool useDiffuseMapForShadowAlpha;
uniform bool alphaTestShadows;

void main(void)
{
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;

    // OPENMW_ANDROID_051_GLES2_NATIVE_SHADOW_CLIPPING
    // GL_DEPTH_CLAMP/ARB_clip_control are unavailable through the GLES2 backend.
    // Deliberately use normal GLES2 near/far clipping here. Per-vertex Z
    // clamping can collapse off-volume caster vertices onto a clip plane and
    // produce large view-dependent triangular shadow projections.

    vec4 viewPos = (gl_ModelViewMatrix * gl_Vertex);
    gl_ClipVertex = viewPos;

    if (useDiffuseMapForShadowAlpha)
        diffuseMapUV = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    else
        diffuseMapUV = vec2(0.0); // Avoid undefined behaviour if running on hardware predating the concept of dynamically uniform expressions
    if (colorMode == 2)
        alphaPassthrough = useTreeAnim ? 1.0 : gl_Color.a;
    else
        // This is uniform, so if it's too low, we might be able to put the position/clip vertex outside the view frustum and skip the fragment shader and rasteriser
        alphaPassthrough = gl_FrontMaterial.diffuse.a;
}
