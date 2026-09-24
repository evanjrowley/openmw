#define SHADOWS @shadows_enabled

#if SHADOWS
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
        uniform mat4 shadowSpaceMatrix@shadow_texture_unit_index;
        varying vec4 shadowSpaceCoords@shadow_texture_unit_index;
        // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1
        // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
        // Local receiver-plane depth slope in normalized shadow UV coordinates.
        // The fragment shader uses this to move each PCF comparison onto the
        // expected depth of the same receiver plane instead of comparing every
        // neighbour against the centre depth.
        varying vec2 shadowReceiverPlaneSlope@shadow_texture_unit_index;

#if @perspectiveShadowMaps
        uniform mat4 validRegionMatrix@shadow_texture_unit_index;
        varying vec4 shadowRegionCoords@shadow_texture_unit_index;
#endif
    @endforeach

    // Enabling this may reduce peter panning. Probably unnecessary.
    const bool onlyNormalOffsetUV = false;
#endif // SHADOWS

#if SHADOWS
vec2 openmwAndroidReceiverPlaneSlope(mat4 shadowMatrix, vec4 shadowCoord, vec3 viewNormal)
{
    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V1
    // Derivative-free receiver-plane depth bias for GLES2/GL4ES.
    // Build two tangents on the receiver plane, project them into shadow
    // coordinates and solve dz/du,dz/dv. This remains valid for the Android
    // orthographic sun map and also handles homogeneous W conservatively.
    float normalLength2 = dot(viewNormal, viewNormal);
    if (normalLength2 < 1e-10 || abs(shadowCoord.w) < 1e-6)
        return vec2(0.0);

    vec3 n = viewNormal * inversesqrt(normalLength2);
    vec3 helperAxis = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 tangentA = normalize(cross(helperAxis, n));
    vec3 tangentB = cross(n, tangentA);

    vec4 projectedA = shadowMatrix * vec4(tangentA, 0.0);
    vec4 projectedB = shadowMatrix * vec4(tangentB, 0.0);

    float invW = 1.0 / shadowCoord.w;
    float invW2 = invW * invW;
    vec3 deltaA = projectedA.xyz * invW - shadowCoord.xyz * projectedA.w * invW2;
    vec3 deltaB = projectedB.xyz * invW - shadowCoord.xyz * projectedB.w * invW2;

    float determinant = deltaA.x * deltaB.y - deltaB.x * deltaA.y;

    // OPENMW_ANDROID_051_GRAZING_SHADOW_FIX_V3
    // Use a scale-independent conditioning test. With the Android orthographic
    // shadow range, valid UV basis determinants are naturally around 1e-8, so
    // the previous absolute 1e-8 cutoff discarded ordinary terrain slopes.
    float determinantScale = length(deltaA.xy) * length(deltaB.xy);
    if (determinantScale < 1e-16)
        return vec2(0.0);

    float minimumDeterminant = determinantScale * 1e-5;
    if (abs(determinant) < minimumDeterminant)
        determinant = determinant < 0.0 ? -minimumDeterminant : minimumDeterminant;

    vec2 receiverSlope = vec2(
        (deltaA.z * deltaB.y - deltaB.z * deltaA.y) / determinant,
        (deltaB.z * deltaA.x - deltaA.z * deltaB.x) / determinant
    );

    // Keep only the mathematically singular horizon case finite.
    return clamp(receiverSlope, vec2(-128.0), vec2(128.0));
}
#endif

void setupShadowCoords(vec4 viewPos, vec3 viewNormal)
{
#if SHADOWS
    vec4 shadowOffset;
    @foreach shadow_texture_unit_index @shadow_texture_unit_list
#if @perspectiveShadowMaps
        shadowRegionCoords@shadow_texture_unit_index = validRegionMatrix@shadow_texture_unit_index * viewPos;
#endif

#if @disableNormalOffsetShadows
        shadowSpaceCoords@shadow_texture_unit_index = shadowSpaceMatrix@shadow_texture_unit_index * viewPos;
#else
        shadowOffset = vec4(viewNormal * @shadowNormalOffset, 0.0);

        if (onlyNormalOffsetUV)
        {
            vec4 lightSpaceXY = viewPos + shadowOffset;
            lightSpaceXY = shadowSpaceMatrix@shadow_texture_unit_index * lightSpaceXY;

            shadowSpaceCoords@shadow_texture_unit_index.xy = lightSpaceXY.xy;
        }
        else
        {
            vec4 offsetViewPosition = viewPos + shadowOffset;
            shadowSpaceCoords@shadow_texture_unit_index = shadowSpaceMatrix@shadow_texture_unit_index * offsetViewPosition;
        }
#endif

        shadowReceiverPlaneSlope@shadow_texture_unit_index = openmwAndroidReceiverPlaneSlope(
            shadowSpaceMatrix@shadow_texture_unit_index,
            shadowSpaceCoords@shadow_texture_unit_index,
            viewNormal
        );
    @endforeach
#endif // SHADOWS
}
