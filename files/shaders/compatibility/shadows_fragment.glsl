#define SHADOWS @shadows_enabled

// OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
// OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V6
// V3 remains the primary plane. Geometry supplies a conditioned, one-sided
// correction measured at each sampled texel, with a bounded depth budget.
//
// OPENMW_ANDROID_051_GLES2_MANUAL_SHADOW_COMPARE
// GLES2/GL4ES: sample OES depth textures through sampler2D and perform
// the LEQUAL test explicitly; EXT_shadow_samplers is not available.
//
// OPENMW_ANDROID_051_GLES2_QUALITY_PCF
// The launcher specializes these two compile-time constants before each game
// start. Keeping the kernel compile-time avoids dynamic loops/branches on GLES2.
// Level 0 = legacy 1 tap, level 1 = 2x2 / 4 taps (Low),
// level 2 = 3x3 / 9 taps (Medium), level 3 = 4x4 / 16 taps (High).
// Level 4 = continuously weighted cubic 4x4 / 16 taps (Very High).
#define OPENMW_ANDROID_SHADOW_PCF_LEVEL 2
#define OPENMW_ANDROID_SHADOW_MAP_RESOLUTION 4096.0

#if SHADOWS
    uniform float maximumShadowMapDistance;
    uniform float shadowFadeStart;
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
        uniform sampler2D shadowTexture@shadow_texture_unit_index;
        varying vec4 shadowSpaceCoords@shadow_texture_unit_index;
        // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1
        varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;

#if @perspectiveShadowMaps
        varying vec4 shadowRegionCoords@shadow_texture_unit_index;
#endif
    @endforeach
#endif // SHADOWS

float openmwAndroidReceiverDepthForOffset(float centerDepth, vec2 receiverPlaneSlope, vec2 texelSize, vec2 texelOffset)
{
    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1
    // Receiver-plane depth bias (RPDB): neighbouring PCF taps must compare
    // against the depth of the same geometric plane at the neighbouring UV,
    // not against the centre fragment depth. This is the key fix for long
    // shadow-acne bands and terrain-triangle artifacts at grazing sun angles.
    return clamp(centerDepth + dot(receiverPlaneSlope, texelSize * texelOffset), 0.0, 1.0);
}

vec2 openmwAndroidGeometricReceiverPlaneSlopeV6(vec3 shadowXYZ, vec2 stableSlope)
{
    // Evaluate before distance/cascade branches. Normalize each derivative by
    // its largest UV component before solving: an absolute determinant cutoff
    // wrongly rejects valid small triangles and distant receivers.
    vec3 dx = dFdx(shadowXYZ);
    vec3 dy = dFdy(shadowXYZ);
    float scaleX = max(abs(dx.x), abs(dx.y));
    float scaleY = max(abs(dy.x), abs(dy.y));
    dx /= max(scaleX, 1e-20);
    dy /= max(scaleY, 1e-20);
    float determinant = dx.x * dy.y - dy.x * dx.y;
    float conditioning = abs(determinant) / max(length(dx.xy) * length(dy.xy), 1e-10);
    if (scaleX < 1e-20 || scaleY < 1e-20 || conditioning <= 0.0001)
        return stableSlope;

    vec2 slope = vec2(dx.z * dy.y - dy.z * dx.y,
                      dy.z * dx.x - dx.z * dy.x) / determinant;
    // Ease back to the interpolated plane near a singular light projection,
    // instead of switching abruptly between unrelated slopes at the horizon.
    float reliability = smoothstep(0.0001, 0.01, conditioning);
    return mix(stableSlope, clamp(slope, vec2(-128.0), vec2(128.0)), reliability);
}

float openmwAndroidConservativeReceiverDepthV6(
    float centerDepth,
    vec2 stableSlope,
    vec2 geometricSlope,
    vec2 texelSize,
    vec2 totalTexelOffset)
{
    // Smoothed rock normals are not the rasterized triangle plane. The V5
    // fixed 0.00010 relief left a depth error at grazing angles, particularly
    // at the outer PCF taps. Correct the actual signed error at this texel.
    // Never raise the V3 comparison depth (the dark-facet regression in V4).
    float stableDepth = openmwAndroidReceiverDepthForOffset(
        centerDepth, stableSlope, texelSize, totalTexelOffset);
    float geometricDepth = openmwAndroidReceiverDepthForOffset(
        centerDepth, geometricSlope, texelSize, totalTexelOffset);
    // Same maximum normalized-depth scale as the existing slope bias. The
    // correction is zero when the planes agree; it is not a global offset or
    // a sun-angle fade of real cast shadows. Singular projections use V3.
    float oneSidedRelief = clamp(stableDepth - geometricDepth, 0.0, 0.0030);
    return max(stableDepth - oneSidedRelief, 0.0);
}

float unshadowedLightRatio(float distance)
{
    float shadowing = 1.0;
#if SHADOWS
    // All derivative evaluations precede even the fade early-return and the
    // cascade-selection branch, so neighbouring fragments share control flow.
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
        float receiverW@shadow_texture_unit_index = shadowSpaceCoords@shadow_texture_unit_index.w;
        vec3 receiverXYZ@shadow_texture_unit_index = shadowSpaceCoords@shadow_texture_unit_index.xyz /
            (abs(receiverW@shadow_texture_unit_index) > 1e-6 ? receiverW@shadow_texture_unit_index : 1e-6);
        vec2 receiverGeometry@shadow_texture_unit_index = openmwAndroidGeometricReceiverPlaneSlopeV6(
            receiverXYZ@shadow_texture_unit_index, shadowReceiverPlaneSlope@shadow_texture_unit_index);
    @endforeach
#if @limitShadowMapDistance
    float fade = clamp((distance - shadowFadeStart) / (maximumShadowMapDistance - shadowFadeStart), 0.0, 1.0);
    if (fade == 1.0)
        return shadowing;
#endif
    bool doneShadows = false;
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
        if (!doneShadows)
        {
            vec3 shadowXYZ = receiverXYZ@shadow_texture_unit_index;
            vec2 stableReceiverPlaneSlope = shadowReceiverPlaneSlope@shadow_texture_unit_index;
            vec2 geometricReceiverPlaneSlope = receiverGeometry@shadow_texture_unit_index;
#if @perspectiveShadowMaps
            vec3 shadowRegionXYZ = shadowRegionCoords@shadow_texture_unit_index.xyz / shadowRegionCoords@shadow_texture_unit_index.w;
#endif
            if (all(lessThan(shadowXYZ.xy, vec2(1.0, 1.0))) && all(greaterThan(shadowXYZ.xy, vec2(0.0, 0.0))))
            {
                // OPENMW_ANDROID_051_GLES2_SHADOW_COORD_BOUNDS
                // Raw GLES2 depth sampling must never compare receivers outside
                // the valid projected shadow depth volume. Otherwise z > 1 can
                // become a view-dependent full-shadow patch with CLAMP_TO_EDGE.
                if (shadowSpaceCoords@shadow_texture_unit_index.w > 0.0 && shadowXYZ.z > 0.0 && shadowXYZ.z < 1.0)
                {
                    vec2 shadowTexel = vec2(1.0 / OPENMW_ANDROID_SHADOW_MAP_RESOLUTION);
                    // OPENMW_ANDROID_051_GLES2_RECEIVER_DEPTH_BIAS
                    // Retain the proven tiny fixed safety bias, then add only a
                    // tightly capped slope-scaled residual for the centre sample.
                    // Most grazing-angle correction happens per PCF tap through
                    // receiver-plane depth reconstruction below, so this does not
                    // require the large global offsets that cause Peter Panning.
                    float receiverDepth = max(shadowXYZ.z - 0.00005, 0.0);
                    vec2 receiverPlaneSlope = stableReceiverPlaneSlope;
                    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
                    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V6
                    // Bounded residual after exact texel-centre reconstruction.
                    float receiverSlopeFootprint =
                        (abs(receiverPlaneSlope.x) + abs(receiverPlaneSlope.y)) * shadowTexel.x;
                    float receiverSlopeBias = min(receiverSlopeFootprint * 0.35, 0.0030);
                    receiverDepth = max(receiverDepth - receiverSlopeBias, 0.0);
#if OPENMW_ANDROID_SHADOW_PCF_LEVEL == 0
                    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
                    vec2 shadowUv = (floor(shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION) + vec2(0.5)) * shadowTexel;
                    shadowUv = clamp(shadowUv, shadowTexel, vec2(1.0) - shadowTexel);
                    vec2 anchorOffset = (shadowUv - shadowXYZ.xy) / shadowTexel;
                    float anchorReceiverDepth = openmwAndroidConservativeReceiverDepthV6(
                        receiverDepth,
                        receiverPlaneSlope,
                        geometricReceiverPlaneSlope,
                        shadowTexel,
                        anchorOffset);
                    shadowing = min(step(anchorReceiverDepth, texture2D(shadowTexture@shadow_texture_unit_index, shadowUv).r), shadowing);
#elif OPENMW_ANDROID_SHADOW_PCF_LEVEL == 1
                    // Low: anchor half-texel taps on a real texel boundary so
                    // all four lookups land at actual texel centres.
                    vec2 shadowUv = floor(
                        shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION + vec2(0.5)) * shadowTexel;
                    shadowUv = clamp(shadowUv, shadowTexel, vec2(1.0) - shadowTexel);
                    vec2 anchorOffset = (shadowUv - shadowXYZ.xy) / shadowTexel;
                    float anchorReceiverDepth = openmwAndroidConservativeReceiverDepthV6(
                        receiverDepth,
                        receiverPlaneSlope,
                        geometricReceiverPlaneSlope,
                        shadowTexel,
                        anchorOffset);
                    float pcfShadow = 0.0;
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5, -0.5)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5, -0.5)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5,  0.5)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5,  0.5)).r);
                    shadowing = min(pcfShadow * 0.25, shadowing);
#elif OPENMW_ANDROID_SHADOW_PCF_LEVEL == 2
                    // Medium: snap the integer 3x3 kernel to the containing
                    // shadow texel centre and reconstruct depth from the original UV.
                    vec2 shadowUv = (floor(shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION) + vec2(0.5)) * shadowTexel;
                    shadowUv = clamp(shadowUv, shadowTexel, vec2(1.0) - shadowTexel);
                    vec2 anchorOffset = (shadowUv - shadowXYZ.xy) / shadowTexel;
                    float anchorReceiverDepth = openmwAndroidConservativeReceiverDepthV6(
                        receiverDepth,
                        receiverPlaneSlope,
                        geometricReceiverPlaneSlope,
                        shadowTexel,
                        anchorOffset);
                    float pcfShadow = 0.0;
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0, -1.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.0, -1.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.0, -1.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0,  0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0,  0.0)).r);
                    pcfShadow += step(anchorReceiverDepth, texture2D(shadowTexture@shadow_texture_unit_index, shadowUv).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.0,  0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.0,  0.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0,  1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0,  1.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.0,  1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.0,  1.0)).r);
                    pcfShadow += step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.0,  1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.0,  1.0)).r);
                    shadowing = min(pcfShadow * (1.0 / 9.0), shadowing);
#elif OPENMW_ANDROID_SHADOW_PCF_LEVEL == 3
                    // High: weighted 4x4 tent PCF at 4096.
                    // OPENMW_ANDROID_051_GLES2_TENT_PCF
                    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
                    // Anchor +/-0.5 and +/-1.5 samples on the nearest real
                    // texel boundary; all sixteen taps then hit distinct centres.
                    vec2 shadowMargin = shadowTexel * 2.0;
                    vec2 shadowUv = floor(
                        shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION + vec2(0.5)) * shadowTexel;
                    shadowUv = clamp(shadowUv, shadowMargin, vec2(1.0) - shadowMargin);
                    vec2 anchorOffset = (shadowUv - shadowXYZ.xy) / shadowTexel;
                    float anchorReceiverDepth = openmwAndroidConservativeReceiverDepthV6(
                        receiverDepth,
                        receiverPlaneSlope,
                        geometricReceiverPlaneSlope,
                        shadowTexel,
                        anchorOffset);
                    float pcfShadow = 0.0;
                    pcfShadow += 1.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.5, -1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.5, -1.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5, -1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5, -1.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5, -1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5, -1.5)).r);
                    pcfShadow += 1.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.5, -1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.5, -1.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.5, -0.5)).r);
                    pcfShadow += 9.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5, -0.5)).r);
                    pcfShadow += 9.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5, -0.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.5, -0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.5, -0.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.5,  0.5)).r);
                    pcfShadow += 9.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5,  0.5)).r);
                    pcfShadow += 9.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5,  0.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.5,  0.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.5,  0.5)).r);
                    pcfShadow += 1.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.5,  1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.5,  1.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-0.5,  1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-0.5,  1.5)).r);
                    pcfShadow += 3.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 0.5,  1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 0.5,  1.5)).r);
                    pcfShadow += 1.0 * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2( 1.5,  1.5)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2( 1.5,  1.5)).r);
                    shadowing = min(pcfShadow * (1.0 / 64.0), shadowing);
#else
                    // OPENMW_ANDROID_051_CONTINUOUS_TENT_PCF_V1
                    // OPENMW_ANDROID_051_CUBIC_PCF_16_V3
                    // Cubic B-spline reconstruction has continuous coverage
                    // AND continuous first derivatives across texel boundaries.
                    // 16 samples, like High; no 36-tap outer skirt or contrast
                    // sharpening. Keep each axis normalized to 9 for the
                    // existing runtime validation contract (2D divisor 81).
                    vec2 grid = clamp(shadowXYZ.xy * OPENMW_ANDROID_SHADOW_MAP_RESOLUTION - vec2(0.5),
                        vec2(1.0), vec2(OPENMW_ANDROID_SHADOW_MAP_RESOLUTION - 3.0));
                    vec2 cell = floor(grid);
                    vec2 f = grid - cell;
                    vec2 g = vec2(1.0) - f;
                    vec2 w0 = g * g * g * 1.5;
                    vec2 w1 = (3.0 * f * f * f - 6.0 * f * f + vec2(4.0)) * 1.5;
                    vec2 w2 = (-3.0 * f * f * f + 3.0 * f * f + 3.0 * f + vec2(1.0)) * 1.5;
                    vec2 w3 = f * f * f * 1.5;
                    vec2 shadowUv = (cell + vec2(0.5)) * shadowTexel;
                    vec2 anchorOffset = (shadowUv - shadowXYZ.xy) / shadowTexel;
                    float pcfShadow = 0.0;
                    pcfShadow += w0.x * w0.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0, -1.0)).r);
                    pcfShadow += w1.x * w0.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(0.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(0.0, -1.0)).r);
                    pcfShadow += w2.x * w0.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(1.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(1.0, -1.0)).r);
                    pcfShadow += w3.x * w0.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(2.0, -1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(2.0, -1.0)).r);
                    pcfShadow += w0.x * w1.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0, 0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0, 0.0)).r);
                    pcfShadow += w1.x * w1.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(0.0, 0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(0.0, 0.0)).r);
                    pcfShadow += w2.x * w1.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(1.0, 0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(1.0, 0.0)).r);
                    pcfShadow += w3.x * w1.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(2.0, 0.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(2.0, 0.0)).r);
                    pcfShadow += w0.x * w2.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0, 1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0, 1.0)).r);
                    pcfShadow += w1.x * w2.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(0.0, 1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(0.0, 1.0)).r);
                    pcfShadow += w2.x * w2.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(1.0, 1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(1.0, 1.0)).r);
                    pcfShadow += w3.x * w2.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(2.0, 1.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(2.0, 1.0)).r);
                    pcfShadow += w0.x * w3.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(-1.0, 2.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(-1.0, 2.0)).r);
                    pcfShadow += w1.x * w3.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(0.0, 2.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(0.0, 2.0)).r);
                    pcfShadow += w2.x * w3.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(1.0, 2.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(1.0, 2.0)).r);
                    pcfShadow += w3.x * w3.y * step(openmwAndroidConservativeReceiverDepthV6(receiverDepth, receiverPlaneSlope, geometricReceiverPlaneSlope, shadowTexel, anchorOffset + vec2(2.0, 2.0)), texture2D(shadowTexture@shadow_texture_unit_index, shadowUv + shadowTexel * vec2(2.0, 2.0)).r);
                    shadowing = min(pcfShadow * (1.0 / 81.0), shadowing);
#endif
                }

                doneShadows = all(lessThan(shadowXYZ, vec3(0.95, 0.95, 1.0))) && all(greaterThan(shadowXYZ, vec3(0.05, 0.05, 0.0)));
#if @perspectiveShadowMaps
                doneShadows = doneShadows && all(lessThan(shadowRegionXYZ, vec3(1.0, 1.0, 1.0))) && all(greaterThan(shadowRegionXYZ.xy, vec2(-1.0, -1.0)));
#endif
            }
        }
    @endforeach
#if @limitShadowMapDistance
    shadowing = mix(shadowing, 1.0, fade);
#endif
#endif // SHADOWS
    return shadowing;
}

void applyShadowDebugOverlay()
{
#if SHADOWS && @useShadowDebugOverlay
    bool doneOverlay = false;
    float colourIndex = 0.0;
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
        if (!doneOverlay)
        {
            vec3 shadowXYZ = shadowSpaceCoords@shadow_texture_unit_index.xyz / shadowSpaceCoords@shadow_texture_unit_index.w;
#if @perspectiveShadowMaps
            vec3 shadowRegionXYZ = shadowRegionCoords@shadow_texture_unit_index.xyz / shadowRegionCoords@shadow_texture_unit_index.w;
#endif
            if (all(lessThan(shadowXYZ.xy, vec2(1.0, 1.0))) && all(greaterThan(shadowXYZ.xy, vec2(0.0, 0.0))))
            {
                colourIndex = mod(@shadow_texture_unit_index.0, 3.0);
                if (colourIndex < 1.0)
                    gl_FragData[0].x += 0.1;
                else if (colourIndex < 2.0)
                    gl_FragData[0].y += 0.1;
                else
                    gl_FragData[0].z += 0.1;

                doneOverlay = all(lessThan(shadowXYZ, vec3(0.95, 0.95, 1.0))) && all(greaterThan(shadowXYZ, vec3(0.05, 0.05, 0.0)));
#if @perspectiveShadowMaps
                doneOverlay = doneOverlay && all(lessThan(shadowRegionXYZ.xyz, vec3(1.0, 1.0, 1.0))) && all(greaterThan(shadowRegionXYZ.xy, vec2(-1.0, -1.0)));
#endif
            }
        }
    @endforeach
#endif // SHADOWS
}
