// OPENMW_ANDROID_051_GL4ES_EXPLICIT_OBJECT_FOG
#ifdef OPENMW_ANDROID_051_GL4ES_EXPLICIT_OBJECT_FOG
uniform vec4 omwFogColor;
uniform float omwFogStart;
uniform float omwFogEnd;
#define OPENMW_FOG_START omwFogStart
#define OPENMW_FOG_END omwFogEnd
#define OPENMW_FOG_SCALE (1.0 / max(omwFogEnd - omwFogStart, 0.0001))
#define OPENMW_FOG_COLOR omwFogColor
#else
#define OPENMW_FOG_START gl_Fog.start
#define OPENMW_FOG_END gl_Fog.end
#define OPENMW_FOG_SCALE gl_Fog.scale
#define OPENMW_FOG_COLOR gl_Fog.color
#endif

#if @skyBlending
#include "lib/core/fragment.h.glsl"

uniform float skyBlendingStart;
#endif

vec4 applyFogAtDist(vec4 color, float euclideanDist, float linearDist, float far)
{
#if @radialFog
    float dist = euclideanDist;
#else
    float dist = abs(linearDist);
#endif
#if @exponentialFog
    float fogValue = 1.0 - exp(-2.0 * max(0.0, dist - OPENMW_FOG_START/2.0) / (OPENMW_FOG_END - OPENMW_FOG_START/2.0));
#else
    float fogValue = clamp((dist - OPENMW_FOG_START) * OPENMW_FOG_SCALE, 0.0, 1.0);
#endif
#ifdef ADDITIVE_BLENDING
    color.xyz *= 1.0 - fogValue;
#else
    color.xyz = mix(color.xyz, OPENMW_FOG_COLOR.xyz, fogValue);
#endif

#if @skyBlending
    float fadeValue = clamp((far - dist) / (far - skyBlendingStart), 0.0, 1.0);
    fadeValue *= fadeValue;
#ifdef ADDITIVE_BLENDING
    color.xyz *= fadeValue;
#else
    color.xyz = mix(sampleSkyColor(gl_FragCoord.xy / screenRes), color.xyz, fadeValue);
#endif
#endif

    return color;
}

vec4 applyFogAtPos(vec4 color, vec3 pos, float far)
{
    return applyFogAtDist(color, length(pos), pos.z, far);
}
