#version 440
// Rain on the glass in front of the view. Drops land and stick, slowly dry
// out, and now and then a big one runs down in jerks, wiping a wet path and
// leaving a line of tiny droplets behind. Each drop is a little lens: it shows
// the scene behind it upside down and squeezed, with a dark rim and a glint.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float time;
    float amount;       // 0 .. 1 how wet the glass is
    float windX;
};
layout(binding = 1) uniform sampler2D scene;

//#include common.glsl

float luma3(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// A drop: x = height (0 at the edge, 1 in the middle), yz = position inside
// the drop (-1 .. 1), w = radius in pixels.
vec4 dropAt(vec2 d, float r, float wobble) {
    float a = atan(d.y, d.x);
    float rr = r * (1.0 + 0.07 * sin(a * 3.0 + wobble) + 0.04 * sin(a * 5.0 + wobble * 2.3));
    float q = 1.0 - dot(d, d) / (rr * rr);
    return q > 0.0 ? vec4(sqrt(q), d / rr, rr) : vec4(0.0);
}

// Drops that land and stay put, then dry (shrink and fade).
vec4 stickyDrops(vec2 px, float cell, float rmin, float rmax, float rate, float seed, float amt) {
    vec2 id = floor(px / cell);
    vec2 f = px - id * cell;
    float h = hash(id + seed);
    float cyc = time * rate + h * 10.0;
    float k = floor(cyc), t = fract(cyc);
    if (hash(id + seed + k * 1.31) > amt) return vec4(0.0);
    vec2 ctr = cell * (0.2 + 0.6 * vec2(hash(id + k * 2.1 + seed), hash(id + k * 3.7 + seed + 1.0)));
    float r = mix(rmin, rmax, pow(hash(id + k * 5.3 + seed), 2.5)) * (1.0 - t * t * 0.5);
    vec2 d = f - ctr;
    d.y *= 1.1;                                                    // gravity flattens them a little
    vec4 drop = dropAt(d, r, h * 40.0 + k);
    drop.x *= smoothstep(1.0, 0.8, t);
    return drop;
}

// x position of a running drop's path at screen height y
float pathX(float col, float colW, float y, float h) {
    float kink = floor(y / 70.0);
    return (col + 0.5 + 0.05 * sin(y * 0.006 + h * 30.0) + 0.05 * (hash(vec2(kink, h)) - 0.5)) * colW;
}

// Big drops running down in jerks. Returns the drop or a trail droplet, and
// how wet the path it has wiped is (that clears the small drops).
vec4 runningDrops(vec2 px, float colW, float seed, float amt, out float wiped) {
    wiped = 0.0;
    float col = floor(px.x / colW);
    float h = hash(vec2(col, seed));
    if (h > amt) return vec4(0.0);
    float H = resolution.y;
    float period = 7.0 + 9.0 * hash(vec2(col, seed + 1.0));
    float t = fract(time / period + h * 7.0);
    // stick and slip: pauses, then lurches
    float s = t + 0.022 * sin(t * 6.2832 * 6.0 + h * 9.0);
    float y = (s * 1.35 - 0.2) * H;
    float r = 5.0 + 6.5 * hash(vec2(col, seed + 2.0));
    float x = pathX(col, colW, y, h);
    vec2 d = px - vec2(x, y);
    d.y *= d.y < 0.0 ? 0.75 : 1.15;                                // rounder underneath, tapered above
    vec4 drop = dropAt(d, r, h * 50.0);
    if (drop.x > 0.0) return drop;
    // the trail: a wet path plus a line of droplets left behind it
    float above = y - px.y;
    float fade = smoothstep(1.0, 0.9, t);
    float len = H * (0.35 + 0.3 * h);
    if (above > 0.0 && above < len) {
        float k = 1.0 - above / len;
        float tx = pathX(col, colW, px.y, h);
        wiped = smoothstep(r * 0.9, r * 0.4, abs(px.x - tx)) * k * fade;
        float seg = 13.0;
        float sid = floor(px.y / seg);
        float sh = hash(vec2(col * 3.1 + sid, seed));
        if (sh > 0.35) {
            vec2 c2 = vec2(pathX(col, colW, (sid + 0.5) * seg, h) + (sh - 0.6) * r * 0.8, (sid + 0.5) * seg);
            vec4 dd = dropAt(px - c2, (1.2 + 2.6 * sh) * k * fade + 0.01, sh * 20.0);
            if (dd.x > 0.0) return dd;
        }
    }
    return vec4(0.0);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * resolution;
    vec3 base = texture(scene, uv).rgb;
    if (amount < 0.005) { fragColor = vec4(base, 1.0) * qt_Opacity; return; }

    float w1, w2;
    vec4 run = runningDrops(px, 95.0, 1.0, amount * 0.55, w1);
    vec4 run2 = runningDrops(px + vec2(47.0, 0.0), 140.0, 5.0, amount * 0.4, w2);
    float wiped = max(w1, w2);
    vec4 big = stickyDrops(px, 46.0, 3.0, 10.5, 0.04, 1.0, amount * 0.9 * (1.0 - wiped));
    vec4 small = stickyDrops(px, 17.0, 0.8, 2.4, 0.06, 4.0, amount * (1.0 - wiped));
    vec4 drop = run;
    if (run2.x > drop.x) drop = run2;
    if (big.x > drop.x) drop = big;
    if (small.x > drop.x) drop = small;

    vec3 col = base;
    if (drop.x > 0.0) {
        // a lens: the view through it is flipped and squeezed
        vec2 rel = drop.yz;
        float r = drop.w;
        vec2 off = -rel * r * (2.2 + 1.5 * (1.0 - drop.x));
        vec2 q = uv + off / resolution;
        // the view through a drop is a little soft
        vec2 b = vec2(1.2) / resolution;
        col = (texture(scene, q).rgb * 2.0 + texture(scene, q + vec2(b.x, 0.0)).rgb
             + texture(scene, q - vec2(b.x, 0.0)).rgb + texture(scene, q + vec2(0.0, b.y)).rgb
             + texture(scene, q - vec2(0.0, b.y)).rgb) / 6.0;
        col *= 1.04;
        // dark rim where light bends out of the drop
        float rim = smoothstep(0.55, 0.0, drop.x);
        col = mix(col, col * 0.35, rim * 0.75);
        // glint from the light above
        float g = smoothstep(0.32, 0.0, length(rel - vec2(-0.32, -0.42)));
        col += g * g * (0.18 + luma3(base) * 0.4);
        // a faint bright crescent at the bottom edge
        col += smoothstep(0.25, 0.0, abs(length(rel) - 0.8)) * step(0.3, rel.y) * 0.05;
    }
    // a wet window lowers contrast slightly
    col = mix(col, vec3(dot(base, vec3(0.333))), amount * 0.04);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
