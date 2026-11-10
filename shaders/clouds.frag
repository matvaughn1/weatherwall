#version 440
// Animated cloud deck seen in perspective, lit by the sun, plus distance haze,
// fog and lightning. Drawn over sky.frag with premultiplied alpha.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec3 sunDir;
    vec3 sunCol;
    vec3 zenCol;
    vec3 horCol;
    vec2 windOffset;
    float coverage;     // 0 .. 1
    float darkness;     // 0 .. 1, rain / storm undersides
    float time;
    float fog;          // 0 .. 1
    float flash;        // lightning, 0 .. 1
    float cityGlow;     // warm light on cloud bases at night
};

//#include common.glsl

float density(vec2 p) {
    float w = fbm(p * 0.45 + vec2(time * 0.004, -time * 0.003));
    float n = fbm(p + w * 1.4 + vec2(-time * 0.002, 0.0));
    float th = mix(0.80, 0.10, coverage);
    return smoothstep(th, th + 0.30, n);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 d = rayDir(uv);
    float hy = horizonY();
    vec3 col = vec3(0.0);
    float a = 0.0;

    vec3 hazeCol = mix(horCol, vec3(dot(horCol, vec3(0.333))), coverage * 0.75);

    if (d.y > 0.0) {
        float t = 1.0 / d.y;                     // distance to a cloud plane at height 1
        vec2 p = d.xz * t * 0.8 + windOffset;
        float dens = density(p);

        vec2 toSun = normalize(sunDir.xz + vec2(1e-4)) * 0.16;
        float shadow = density(p + toSun);
        float lightAmt = clamp(1.1 - shadow * 0.95, 0.0, 1.0);
        float sunUp = smoothstep(-0.08, 0.05, sunDir.y) * (1.0 - coverage * 0.55);

        vec3 amb = mix(zenCol, horCol, 0.35) * 0.95 + vec3(0.02, 0.026, 0.045);
        amb = mix(amb, vec3(dot(amb, vec3(0.333))), coverage * 0.8);
        amb += vec3(0.075, 0.062, 0.058) * cityGlow;   // town lights on low cloud

        vec3 c = amb * (1.2 - dens * 0.5);
        c += sunCol * lightAmt * sunUp * (0.9 - dens * 0.35);
        float cosA = max(dot(d, sunDir), 0.0);
        c += sunCol * sunUp * pow(cosA, 10.0) * (1.0 - dens) * 1.8;     // silver lining
        c *= 1.0 - darkness * 0.6 * smoothstep(0.15, 1.0, dens);
        c += vec3(0.8, 0.85, 1.0) * flash * (0.3 + dens);

        float haze = 1.0 - exp(-t * 0.05);
        c = mix(c, hazeCol, haze * 0.9);
        col = c;
        a = clamp(dens * smoothstep(0.0, 0.05, d.y) + haze * coverage * coverage, 0.0, 1.0);
    }

    // clouds and haze stay behind the mountains
    float behind = smoothstep(mountainTop(uv.x * resolution.x / resolution.y) - 0.002,
                              mountainTop(uv.x * resolution.x / resolution.y) + 0.002, uv.y);
    a *= 1.0 - behind;
    col *= 1.0 - behind;

    // fog: thicker toward the ground
    float f = fog * clamp(0.3 + 0.7 * smoothstep(0.15, hy + 0.08, uv.y), 0.0, 1.0);
    vec3 fc = mix(hazeCol, vec3(dot(hazeCol, vec3(0.333))), 0.5) * 1.05 + vec3(0.8) * flash * 0.3;
    vec3 pm = col * a * (1.0 - f) + fc * f;      // premultiplied
    a = a * (1.0 - f) + f;

    fragColor = vec4(pm, a) * qt_Opacity;
}
