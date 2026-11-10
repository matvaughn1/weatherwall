#version 440
// Foreground: covered back patio. Eave across the top, warm string lights that
// sway with the wind, and a wooden railing you look out over. Premultiplied
// alpha: solid wood has alpha 1, light glow is added on top with alpha 0.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec3 sunDir;
    vec3 sunCol;
    vec3 zenCol;
    float time;
    float lightsOn;     // 0 .. 1
    float windAmt;      // 0 .. 1
    float snowGround;   // 0 .. 1
    float wet;          // 0 .. 1
    vec3 pal1;          // string light colours (warm white unless it's a holiday)
    vec3 pal2;
    vec3 pal3;
    float railing;      // 1 = full patio, 0 = just the string lights
    float multi;        // 1 = classic multicolour strand
};

//#include common.glsl

const vec3 WARM = vec3(1.0, 0.6, 0.26);
const float SPAN_WANT = 0.95; // rough distance between strand hooks (screen heights)
const float BULB_WANT = 0.058; // rough bulb spacing
const float HOOK_Y = -0.004;  // hooks just above the top edge: strands hang from the top of the screen
// Strands are fitted to the screen with a hook at each edge, so the strings
// on side-by-side monitors meet at the bezel instead of being cut off mid-swoop.
float SPAN;
float BULB;

float sagOf(float i) { return 0.085 + 0.035 * hash(vec2(i, 3.1)); }

float strandY(float ax, float i) {
    float x0 = i * SPAN;
    float m = clamp((ax - x0) / SPAN, 0.0, 1.0);
    float sway = sin(time * (0.5 + 0.2 * hash(vec2(i, 9.0))) + i * 1.7) * 0.012 * (0.3 + windAmt);
    return HOOK_Y + (sagOf(i) + sway) * 4.0 * m * (1.0 - m);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = resolution.x / resolution.y;
    float ax = uv.x * aspect;
    float px = 1.0 / resolution.y;

    vec3 col = vec3(0.0);
    float alpha = 0.0;
    vec3 glow = vec3(0.0);

    // light on the wood: sky ambient + (backlit, so weak) sun + the string lights
    float sunAmt = max(sunDir.y, 0.0);
    vec3 dayLight = zenCol * 0.55 + sunCol * sunAmt * 0.25 + vec3(0.008, 0.009, 0.012);

    // ── String lights ──
    SPAN = aspect / max(1.0, floor(aspect / SPAN_WANT + 0.5));
    BULB = SPAN / floor(SPAN / BULB_WANT + 0.5);
    float i = floor(ax / SPAN);
    float yc = strandY(ax, i);
    float x0 = i * SPAN;

    float wire = smoothstep(1.6 * px, 0.4 * px, abs(uv.y - yc));
    col = mix(col, vec3(0.02), wire); alpha = max(alpha, wire);

    // broad warm wash around the strand
    glow += WARM * lightsOn * 0.10 * exp(-abs(uv.y - yc - 0.015) * 14.0);

    float k = floor((ax - x0) / BULB);
    for (int j = -1; j <= 1; j++) {
        float bk = k + float(j);
        float bx = x0 + (bk + 0.5) * BULB;
        if (bx < x0 || bx > x0 + SPAN) continue;
        float by = strandY(bx, i) + 0.016;
        vec2 dv = vec2(ax - bx, uv.y - by);
        float var = 0.85 + 0.15 * hash(vec2(bk, i));     // each bulb a touch different
        float pm = mod(bk, 3.0);
        vec3 bc = pm < 1.0 ? pal1 : (pm < 2.0 ? pal2 : pal3);
        if (multi > 0.5) {                                 // red, green, blue, orange, purple
            float pm5 = mod(bk + i * 2.0, 5.0);
            bc = pm5 < 1.0 ? vec3(1.0, 0.1, 0.08) : pm5 < 2.0 ? vec3(0.12, 0.9, 0.25)
               : pm5 < 3.0 ? vec3(0.18, 0.35, 1.0) : pm5 < 4.0 ? vec3(1.0, 0.5, 0.06) : vec3(0.65, 0.2, 1.0);
        }

        // socket
        float sock = step(abs(dv.x), 0.0032) * step(by - 0.014, uv.y) * step(uv.y, by - 0.006);
        col = mix(col, vec3(0.015), sock); alpha = max(alpha, sock);

        // bulb glass
        float e = length(dv / vec2(0.0062, 0.0085));
        float glass = smoothstep(1.0, 0.8, e);
        vec3 bulbOn = mix(bc, mix(bc, vec3(1.0), 0.6), smoothstep(0.9, 0.2, e)) * 1.25 * var;
        vec3 bulbOff = vec3(0.55, 0.5, 0.42) * dayLight * 1.4 + vec3(0.03);
        col = mix(col, mix(bulbOff, bulbOn, lightsOn), glass); alpha = max(alpha, glass);

        // halo
        float d2 = dot(dv, dv);
        glow += bc * var * lightsOn * (exp(-d2 / 0.00022) * 0.55 + exp(-sqrt(d2) / 0.035) * 0.10);
    }

    // ── Eave / gutter across the top ──
    float eave = smoothstep(0.022 + px, 0.022 - px, uv.y);
    vec3 eaveCol = vec3(0.16, 0.11, 0.075) * dayLight * 0.6 + WARM * lightsOn * 0.12
                 * smoothstep(0.0, 0.022, uv.y);
    eave *= railing;
    col = mix(col, eaveCol, eave); alpha = max(alpha, eave);

    // ── Railing ──
    const float RAIL_T = 0.885, RAIL_B = 0.905;     // top rail
    const float LOW_T = 0.975, LOW_B = 0.986;       // bottom rail
    float grain = 0.82 + 0.3 * fbm(vec2(ax * 3.0, uv.y * 220.0));
    vec3 wood = vec3(0.36, 0.22, 0.13) * grain;
    // string lights are above, so tops catch more light and it falls off downward
    float fall = 1.0 - smoothstep(0.88, 1.0, uv.y) * 0.55;
    vec3 warmLight = WARM * lightsOn * 0.75 * fall;
    vec3 lit = dayLight + warmLight;

    float topRail = step(RAIL_T, uv.y) * step(uv.y, RAIL_B);
    float lowRail = step(LOW_T, uv.y) * step(uv.y, LOW_B);
    float postX = fract(ax / 0.85 + 0.37);
    float post = step(RAIL_T - 0.012, uv.y) * step(abs(postX - 0.5) * 0.85, 0.018);
    float bal = step(RAIL_B, uv.y) * step(uv.y, LOW_T) * step(abs(fract(ax / 0.042) - 0.5) * 0.042, 0.0045);
    float deck = step(LOW_B, uv.y);
    float solid = max(max(topRail, lowRail), max(max(post, bal), deck)) * railing;

    vec3 woodCol = wood * lit;
    // rail top edge highlight, wetter = shinier
    float edge = smoothstep(RAIL_T + 0.004, RAIL_T, uv.y) * topRail;
    woodCol += edge * (WARM * lightsOn * (0.35 + wet * 0.6) + dayLight * 0.4);
    // snow sitting on the rail
    float snowCap = step(RAIL_T - 0.012 * snowGround, uv.y) * step(uv.y, RAIL_T + 0.002) * step(0.01, snowGround);
    woodCol = mix(woodCol, vec3(0.85, 0.88, 0.92) * (dayLight * 1.4 + warmLight * 0.8), snowCap);
    // posts a little darker on their shaded side, deck boards
    woodCol *= 1.0 - post * 0.15 * step(postX, 0.5);
    woodCol *= 1.0 - deck * 0.35 * step(0.9, fract(ax * 9.0));

    col = mix(col, woodCol, solid);
    alpha = max(alpha, solid);

    // camera vignette: darken the edges of whatever is behind
    vec2 vq = (uv - 0.5) * vec2(aspect / 2.2, 1.0);
    float vig = smoothstep(0.35, 0.95, length(vq)) * 0.45 * railing;   // photo mode has its own

    // premultiplied: wood/bulbs replace what's behind, glow adds on top
    vec3 outc = col * alpha * (1.0 - vig) + glow;
    float outa = alpha + (1.0 - alpha) * vig;
    fragColor = vec4(outc, outa) * qt_Opacity;
}
