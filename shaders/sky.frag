#version 440
// Sky (single-scattering atmosphere), sun disc, stars, moon with phase, and the
// hill silhouette. Only re-rendered when the sun moves (about once a minute).
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
    vec3 moonDir;
    float moonPhase;    // 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
    float snowGround;   // 0 bare hills .. 1 snow covered
    float overcast;     // 0 .. 1
    float fog;          // 0 .. 1
    float mountainSnow; // 0 .. 1, how far down the peaks are white
};

//#include common.glsl

#define ISTEPS 12
#define JSTEPS 4

vec2 rsi(vec3 r0, vec3 rd, float sr) {
    float a = dot(rd, rd);
    float b = 2.0 * dot(rd, r0);
    float c = dot(r0, r0) - sr * sr;
    float d = b * b - 4.0 * a * c;
    if (d < 0.0) return vec2(1e5, -1e5);
    return vec2((-b - sqrt(d)) / (2.0 * a), (-b + sqrt(d)) / (2.0 * a));
}

// After wwwtyro/glsl-atmosphere (Unlicense)
vec3 atmosphere(vec3 r, vec3 pSun) {
    const vec3 r0 = vec3(0.0, 6372e3, 0.0);
    const float rPlanet = 6371e3, rAtmos = 6471e3;
    const vec3 kRlh = vec3(5.5e-6, 13.0e-6, 22.4e-6);
    const float kMie = 21e-6, shRlh = 8e3, shMie = 1.2e3, g = 0.758, iSun = 22.0;

    vec2 p = rsi(r0, r, rAtmos);
    if (p.x > p.y) return vec3(0.0);
    p.y = min(p.y, rsi(r0, r, rPlanet).x);
    float iStep = (p.y - p.x) / float(ISTEPS);
    float iTime = 0.0;
    vec3 totalRlh = vec3(0.0), totalMie = vec3(0.0);
    float iOdRlh = 0.0, iOdMie = 0.0;
    float mu = dot(r, pSun), mumu = mu * mu, gg = g * g;
    float pRlh = 3.0 / (16.0 * PI) * (1.0 + mumu);
    float pMie = 3.0 / (8.0 * PI) * ((1.0 - gg) * (mumu + 1.0)) /
                 (pow(1.0 + gg - 2.0 * mu * g, 1.5) * (2.0 + gg));
    for (int i = 0; i < ISTEPS; i++) {
        vec3 iPos = r0 + r * (iTime + iStep * 0.5);
        float iHeight = length(iPos) - rPlanet;
        float odR = exp(-iHeight / shRlh) * iStep;
        float odM = exp(-iHeight / shMie) * iStep;
        iOdRlh += odR; iOdMie += odM;
        float jStep = rsi(iPos, pSun, rAtmos).y / float(JSTEPS);
        float jTime = 0.0, jOdRlh = 0.0, jOdMie = 0.0;
        for (int j = 0; j < JSTEPS; j++) {
            vec3 jPos = iPos + pSun * (jTime + jStep * 0.5);
            float jHeight = length(jPos) - rPlanet;
            jOdRlh += exp(-jHeight / shRlh) * jStep;
            jOdMie += exp(-jHeight / shMie) * jStep;
            jTime += jStep;
        }
        vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));
        totalRlh += odR * attn;
        totalMie += odM * attn;
        iTime += iStep;
    }
    return iSun * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 d = rayDir(uv);
    float hy = horizonY();
    float nightness = smoothstep(0.02, -0.15, sunDir.y);

    // ── Sky ──
    vec3 col = 1.0 - exp(-atmosphere(normalize(vec3(d.x, max(d.y, 0.002), d.z)), sunDir));
    col += vec3(0.010, 0.015, 0.035) * (1.3 - d.y);     // night floor (airglow / moonlight)

    // stars: hashed 3px cells, fading out toward the horizon
    vec2 cell = floor(uv * resolution / 3.0);
    float h = hash(cell);
    if (h > 0.9965) {
        float b = pow((h - 0.9965) / 0.0035, 3.0);
        col += vec3(0.85, 0.9, 1.0) * b * nightness * smoothstep(0.02, 0.25, d.y);
    }

    // moon
    float moonUp = smoothstep(-0.01, 0.04, moonDir.y);
    float cosM = dot(d, moonDir);
    const float MR = 0.02;
    vec3 mR = normalize(cross(vec3(0.0, 1.0, 0.0), moonDir));
    vec3 mU = cross(moonDir, mR);
    vec2 lc = vec2(dot(d, mR), dot(d, mU)) / MR;
    float lit = 0.5 - 0.5 * cos(moonPhase * 2.0 * PI);     // 0 new .. 1 full
    if (cosM > 0.0 && length(lc) < 1.0) {
        vec3 n = vec3(lc, sqrt(1.0 - dot(lc, lc)));
        float a = moonPhase * 2.0 * PI;
        vec3 L = vec3(sin(a), 0.0, -cos(a));
        float shade = max(dot(n, L), 0.0);
        float maria = 0.78 + 0.22 * noise(lc * 2.5 + 7.0);
        vec3 mc = vec3(0.95, 0.93, 0.87) * (shade * maria + 0.025);
        float edge = smoothstep(1.0, 0.94, length(lc));
        col = mix(col, col * 0.3 + mc, edge * moonUp * mix(1.0, 0.35, 1.0 - nightness));
    }
    col += vec3(0.6, 0.65, 0.75) * pow(max(cosM, 0.0), 4000.0) * 0.12 * lit * moonUp;

    // sun disc + glow
    float cosA = dot(d, sunDir);
    float disc = smoothstep(cos(0.017), cos(0.0145), cosA);
    float sunUp = smoothstep(-0.03, 0.01, sunDir.y);
    col += sunCol * (pow(max(cosA, 0.0), 2500.0) * 0.6 + pow(max(cosA, 0.0), 120.0) * 0.12) * sunUp;
    col = mix(col, mix(sunCol, vec3(1.0, 0.98, 0.92), 0.5) * 1.3, disc * sunUp);

    // ── Mountains (Cascades-style) and forested foothills ──
    float ax = uv.x * resolution.x / resolution.y;
    float aaY = 1.5 / resolution.y;
    float sunAmt = max(sunDir.y, 0.0) * (1.0 - overcast * 0.85);
    vec3 amb = mix(zenCol, vec3(dot(zenCol, vec3(0.333))), overcast * 0.7) * 0.6 + vec3(0.008, 0.01, 0.016);
    vec3 fogCol = mix(horCol, vec3(dot(horCol, vec3(0.333))), overcast * 0.75);

    float mx = ax * 0.55 + 4.0;
    float mTop = mountainTop(ax);
    float slopeM = ridge(mx + 0.01, 1.9) - ridge(mx - 0.01, 1.9);
    float facing = clamp(0.55 + slopeM * 6.0 * sign(sunDir.x + 1e-4), 0.15, 1.0);
    vec3 rock = vec3(0.30, 0.31, 0.33) * (0.75 + 0.3 * fbm(vec2(ax * 18.0, uv.y * 30.0)));
    float capDepth = mountainSnow * (0.05 + 0.06 * fbm(vec2(ax * 9.0, 2.0)));
    float cap = smoothstep(mTop + capDepth + 0.006, mTop + capDepth - 0.004, uv.y);
    vec3 mSurf = mix(rock * vec3(0.55, 0.62, 0.55), vec3(0.92, 0.94, 0.97), cap);
    vec3 mCol = mSurf * (amb * 1.2 + sunCol * sunAmt * facing * 0.9);
    mCol = mix(mCol, horCol * 0.95, 0.28);                  // distance haze
    mCol = mix(mCol, fogCol, clamp(fog * 1.15, 0.0, 1.0));
    col = mix(col, mCol, smoothstep(mTop - aaY, mTop + aaY, uv.y));

    float fTop = hy - 0.012 - 0.05 * ridge(ax * 1.4 + 7.0, 6.3);
    float trees = 0.75 + 0.5 * noise(vec2(ax * 260.0, uv.y * 90.0));
    vec3 forest = mix(vec3(0.05, 0.10, 0.07) * trees, vec3(0.85, 0.88, 0.92), mountainSnow * 0.55 * trees);
    vec3 fCol = forest * (amb * 1.3 + sunCol * sunAmt * 0.6);
    fCol = mix(fCol, horCol * 0.85, 0.25);
    fCol = mix(fCol, fogCol, clamp(fog * 0.95, 0.0, 1.0));
    col = mix(col, fCol, smoothstep(fTop - aaY, fTop + aaY, uv.y));

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
