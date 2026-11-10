#version 440
// A real photo with live weather applied, using its depth/segmentation maps
// from tools/analyze.py: snow settles on up-facing surfaces, the ground gets
// wet with reflective puddles and splashes, rain and snow fall at real depths
// (hidden behind nearer things), fog banks roll through the valleys, windows
// glow at night, fireworks go off behind the skyline and lightning lights up
// the sky.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float photoAspect;
    float zoom;         // slow camera drift (Ken Burns)
    vec2 pan;
    float time;
    float relight;      // 0 .. 1: turn a daytime photo into night
    float dusk;         // 0 .. 1: warm golden-hour grade
    float lightsOn;     // 0 .. 1
    float snow;         // 0 .. 1 snow to add on surfaces
    float snowing;      // 0 .. 1 falling now
    float wetness;      // 0 .. 1
    float rain;         // 0 .. 1 falling now
    float fog;          // 0 .. 1
    float flash;        // lightning
    float windAmt;      // 0 .. 1
    float windX;        // -1 .. 1 screen direction of the wind
    float gloom;        // 0 .. 1 overcast/storm darkening of a sunny photo
    float skyMix;       // 0 .. 1 replace the photo's sky with the live sky
    vec3 fogCol;
    vec3 pal1;          // holiday light colours
    vec3 pal2;
    vec3 pal3;
    float decorOn;      // 0 .. 1, holiday decorations up
    vec3 fwLight;       // light thrown on the scene by the last firework burst
    float fwOn;         // 0 .. 1 fireworks texture in use
};
layout(binding = 1) uniform sampler2D photo;
layout(binding = 2) uniform sampler2D maps;
layout(binding = 3) uniform sampler2D maps2;
layout(binding = 4) uniform sampler2D liveSky;
layout(binding = 5) uniform sampler2D decor;
layout(binding = 6) uniform sampler2D fw;       // fireworks, screen space, premultiplied
layout(binding = 7) uniform sampler2D maps3;    // R = water, G = plants
layout(binding = 8) uniform sampler2D skyMask;  // fine sky mask (tools/skyline.py)
layout(binding = 9) uniform sampler2D props;    // holiday props (tools/props.py), premultiplied
layout(binding = 10) uniform sampler2D propsGlow; // light the props give off

//#include common.glsl

const vec3 WARM = vec3(1.0, 0.64, 0.32);

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// ── Falling rain ────────────────────────────────────────────────────────────
// One depth layer of drops, in screen pixels. A camera at ~1/60 s sees each
// drop as a thin motion-blurred streak: near drops are long, wide and faint
// (out of focus), far ones short and sharp. Columns hold drops at random
// heights so there's no visible grid.
float rainStreaks(vec2 px, float colW, float spacing, float len, float width,
                  float speed, float density, float seed) {
    px.x += px.y * windX * 0.22;                              // slant with the wind
    float col = floor(px.x / colW);
    float y = px.y - time * speed - hash(vec2(col, seed)) * 7000.0;
    float row = floor(y / spacing);
    float fy = y - row * spacing;
    vec2 id = vec2(col + seed * 17.0, row);
    if (hash(id) > density) return 0.0;
    float h2 = hash(id + 3.1), h3 = hash(id + 7.7);
    float l = len * (0.65 + 0.7 * h2);
    float s0 = h3 * (spacing - l);
    float along = smoothstep(s0, s0 + l * 0.35, fy) * smoothstep(s0 + l, s0 + l * 0.55, fy);
    float x = (col + 0.15 + 0.7 * hash(id + 11.3)) * colW;
    float dx = abs(px.x - x);
    float across = smoothstep(width + 0.8, max(width - 0.8, 0.0), dx);
    return along * across * (0.6 + 0.4 * h2);
}

// Splashes where drops hit the ground: a quick flattened crown that spreads
// and fades, bigger close up.
float splashes(vec2 px, float near, float rate) {
    float cell = 26.0;
    vec2 id = floor(px / cell);
    vec2 f = px - id * cell;
    float h = hash(id + 0.37);
    float cyc = time * rate + h * 13.0;
    float t = fract(cyc);
    float k = floor(cyc);
    if (t > 0.16) return 0.0;
    t /= 0.16;
    vec2 c = cell * (0.2 + 0.6 * vec2(hash(id + k * 1.7), hash(id + k * 2.9 + 4.0)));
    vec2 d = f - c;
    float size = 1.5 + 6.0 * near;
    float r = size * sqrt(t);
    float ring = smoothstep(1.2, 0.0, abs(length(d * vec2(1.0, 3.2)) - r)) * (d.y < 0.5 ? 1.0 : 0.25);
    // droplets thrown up
    vec2 up = d - vec2(0.0, -size * 1.4 * t * (1.0 - t) * 2.0);
    float spray = smoothstep(1.1, 0.2, length(up * vec2(0.8, 1.0)));
    return (ring * 0.8 + spray * 0.6) * (1.0 - t);
}

// ── Falling snow ────────────────────────────────────────────────────────────
// Each flake drifts and sways inside its own cell while the whole layer falls.
// Near flakes are big soft out-of-focus discs, far ones tiny sharp dots.
float snowFlakes(vec2 px, float cell, float radius, float blur, float speed, float density, float seed) {
    px.y -= time * speed;
    px.x -= time * speed * windX * 0.7;
    vec2 id = floor(px / cell);
    vec2 f = px - id * cell;
    float h = hash(id + seed);
    if (h > density) return 0.0;
    vec2 c = cell * (0.3 + 0.4 * vec2(hash(id + seed + 1.3), hash(id + seed + 2.7)));
    c.x += sin(time * (0.7 + h) + h * 30.0) * cell * 0.16;
    c.y += cos(time * (0.5 + h) * 0.8 + h * 17.0) * cell * 0.07;
    float r = radius * (0.55 + 0.9 * hash(id + seed + 5.1));
    float d = length(f - c);
    return smoothstep(r + blur, max(r - blur, 0.0), d) * (0.7 + 0.3 * h / max(density, 0.01));
}

// ── Fog banks ───────────────────────────────────────────────────────────────
// Two scales of noise drifting with the wind. Fog fills in from the distance
// and the low ground first, so when it thickens it rolls in toward you.
float fogAmount(vec2 uv, float sa, float dist, out float wisp) {
    vec2 q = vec2(uv.x * sa, uv.y);
    float dir = windX >= 0.0 ? 1.0 : -1.0;
    float spd = 0.6 + windAmt * 2.0;
    float n1 = fbm(q * vec2(1.1, 3.0) + vec2(-time * 0.012 * dir * spd, 0.0));
    float n2 = fbm(q * vec2(3.2, 7.5) + vec2(-time * 0.03 * dir * spd, time * 0.004) + n1 * 1.4);
    float bank = n1 * 0.6 + n2 * 0.5;
    float depthF = pow(dist, 0.55);
    float low = smoothstep(0.3, 0.9, uv.y);
    float roll = fog * 1.25;
    float amt = smoothstep(1.05 - roll, 1.4 - roll, depthF * 0.75 + bank * 0.6 + low * 0.15);
    amt *= clamp(fog * 1.15, 0.0, 1.0) * (0.35 + 0.65 * depthF);
    // thin wisps passing in front of nearer things
    wisp = smoothstep(0.55, 0.85, fbm(q * vec2(2.0, 6.0) + vec2(-time * 0.045 * dir * spd, 0.0) + 7.0))
         * smoothstep(0.35, 0.8, fog) * (1.0 - depthF * 0.4);
    return clamp(amt, 0.0, 1.0) * (0.8 + 0.2 * n2);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float sa = resolution.x / resolution.y;
    vec2 px = uv * resolution;

    // cover-fit the photo, then the slow camera drift
    vec2 puv = uv;
    if (photoAspect > sa) puv.x = 0.5 + (uv.x - 0.5) * sa / photoAspect;
    else                  puv.y = 0.5 + (uv.y - 0.5) * photoAspect / sa;
    puv = 0.5 + (puv - 0.5) / zoom + pan;

    vec3 c = texture(photo, puv).rgb;
    vec4 m = texture(maps, puv);
    vec4 m2 = texture(maps2, puv);
    float sky = texture(skyMask, puv).r;
    // the coarse depth map counts edge pixels as sky (far away); where the fine
    // mask says they're treetops or roofs, put them at a middle distance
    float dist = max(mix(m.r, min(m.r, 0.6), clamp((m.g - sky) * 1.5, 0.0, 1.0)), sky);
    float ground = m.b * (1.0 - sky), water = texture(maps3, puv).r * (1.0 - sky);
    float up = m2.r, lights = m2.g, mirrorY = m2.b;
    float lum = luma(c);
    float near = 1.0 - dist;

    // ── live sky in place of the photo's sky ──
    if (skyMix > 0.0) c = mix(c, texture(liveSky, vec2(uv.x, uv.y * 0.42)).rgb, sky * skyMix);

    // ── holiday props: lit to match the photo around them ──
    vec4 pr = decorOn > 0.0 ? texture(props, puv) : vec4(0.0);
    if (pr.a > 0.004) {
        float amb = 0.0;
        for (int i = 0; i < 4; i++) {
            vec2 o = vec2(cos(float(i) * 1.57 + 0.8), sin(float(i) * 1.57 + 0.8)) * 0.03;
            amb += luma(texture(photo, puv + o).rgb);
        }
        amb /= 4.0;
        c = c * (1.0 - pr.a) + pr.rgb * clamp(0.35 + amb * 1.25, 0.35, 1.25);
        lum = luma(c);
    }

    // ── wet ground, puddles and reflections ──
    float wetG = ground * wetness * (1.0 - snow);
    float wetW = water * rain;
    if (wetG + wetW > 0.01 && mirrorY > 0.0) {
        float th = mix(0.78, 0.5, wetness);
        float puddle = smoothstep(th, th + 0.05, fbm(puv * vec2(7.0, 22.0) + 4.0)) * step(0.3, wetness);
        // rain rings disturb the reflection
        vec2 rp = puv * vec2(60.0, 140.0);
        vec2 cell = floor(rp);
        vec2 f = fract(rp) - 0.5;
        float t = fract(time * 1.1 + hash(cell));
        float ring = sin((length(f) - t * 0.5) * 40.0) * smoothstep(0.5 * t + 0.1, 0.5 * t, length(f)) * (1.0 - t);
        vec2 rq = vec2(puv.x, 2.0 * mirrorY - puv.y) + vec2(ring, ring) * 0.002 * rain * puddle;
        vec3 refl = texture(photo, rq).rgb;
        if (skyMix > 0.0) refl = mix(refl, texture(liveSky, vec2(uv.x, clamp(rq.y, 0.0, 1.0) * 0.42)).rgb, texture(skyMask, rq).r * skyMix);
        c *= 1.0 - 0.45 * wetG;                             // wet surfaces go darker
        c = mix(c, c * 1.15 + (c - vec3(luma(c))) * 0.25, wetG);   // and richer
        float r = (puddle * 0.75 + 0.18) * wetG * (0.55 + 0.45 * dist);
        c = mix(c, refl * 0.85, r);
    }

    // ── overcast / storm takes the sun out of a sunny photo ──
    c = mix(c, vec3(luma(c)) * vec3(0.92, 0.95, 1.0) * 0.8, gloom * 0.6);
    // rain: flat light, less colour, lower contrast
    c = mix(c, vec3(luma(c)) * 0.9 + fogCol * 0.08, rain * 0.25);

    // ── golden hour ──
    c = mix(c, c * vec3(1.18, 0.92, 0.72), dusk * 0.55);

    // ── night: relight a daytime photo, windows and lamps come on ──
    vec3 nightC = c * vec3(0.10, 0.13, 0.22) + vec3(0.004, 0.006, 0.012);
    float litHash = hash(floor(puv * vec2(90.0, 60.0)));
    vec3 windowCol = WARM * (0.75 + 0.5 * litHash) * step(0.25, litHash);
    nightC = mix(nightC, windowCol * 1.1, lights * step(0.3, lights));
    c = mix(c, nightC, relight);

    // glow (bloom) around light sources, bigger in rain and fog
    float rad = 0.006 * (1.0 + fog * 2.0 + rain * 1.5);
    float glow = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785;
        glow += texture(maps2, puv + vec2(cos(a), sin(a) * sa / photoAspect) * rad).g;
        glow += texture(maps2, puv + vec2(cos(a + 0.4), sin(a + 0.4) * sa / photoAspect) * rad * 2.5).g * 0.6;
    }
    c += WARM * glow / 12.8 * lightsOn * 0.5 * (1.0 + fog + rain);

    // ── snow builds up on whatever faces up ──
    // patchy: drifts and bare spots at a few scales; thin edges stay mostly bare
    float patchy = fbm(puv * vec2(30.0, 55.0)) * 0.6 + noise(puv * vec2(420.0, 600.0)) * 0.4;
    // flat ground and far hillsides whiten evenly; up-facing edges catch a bit more
    float flatG = max(ground * 0.85, smoothstep(0.45, 0.9, dist) * 0.6);
    float sn = snow * clamp(max(flatG, smoothstep(0.3, 0.9, up) * 0.8) + (patchy - 0.5) * 0.5, 0.0, 1.0)
             * (1.0 - sky) * (1.0 - water);
    // snow takes the light and shade of what it lies on, so the photo's texture shows through
    float shade = 0.5 + 0.75 * lum;
    float snowLight = shade * mix(1.0, 0.16, max(relight, lightsOn * 0.8));
    vec3 snowC = vec3(0.90, 0.93, 0.98) * snowLight + WARM * glow / 12.8 * lightsOn * 0.6;
    c = mix(c, snowC, clamp(sn * 1.15, 0.0, 0.88));

    // carved pumpkins, tree bulbs: they glow at dusk and night
    if (decorOn > 0.0) c += texture(propsGlow, puv).rgb * 2.0 * (0.12 + 0.88 * max(lightsOn, relight)) * (1.0 + fog * 0.5);

    // ── holiday lights on the rooflines and in the trees ──
    if (decorOn > 0.0) {
        vec4 dc = texture(decor, puv);
        if (dc.r + dc.b > 0.003) {
            vec3 bc = dc.g < 0.25 ? pal1 : (dc.g < 0.75 ? pal2 : pal3);
            float ph = hash(floor(puv * vec2(700.0, 400.0)));
            float tw = 0.75 + 0.25 * sin(time * (0.6 + ph * 1.2) + ph * 40.0);
            float on = decorOn * (0.35 + 0.65 * lightsOn) * tw;
            c = mix(c, mix(bc, vec3(1.0), 0.35) * 1.4, dc.r * on);           // the bulbs
            c += bc * dc.b * on * (0.25 + lightsOn * 0.35) * (1.0 + fog);     // their glow
        }
    }

    // ── fireworks: in the sky, behind anything nearer; they light up the town ──
    if (fwOn > 0.0) {
        float open = max(sky, smoothstep(0.88, 0.98, dist));
        c += texture(fw, uv).rgb * open;
        float facing = 0.35 + 0.65 * smoothstep(0.0, 0.6, 1.0 - up);       // walls catch more than the ground
        c += fwLight * (1.0 - sky) * (0.05 + c * 1.6) * facing * (1.0 - dist * 0.5);
        c += fwLight * sky * 0.06;                                         // smoke and haze glow
        if (water > 0.05 && mirrorY > 0.0) {                               // reflected in water
            // the mirror line is in photo space; bring it to the screen
            float fy = 0.5 + (mirrorY - pan.y - 0.5) * zoom;
            float my = photoAspect > sa ? fy : 0.5 + (fy - 0.5) * sa / photoAspect;
            vec2 rq = vec2(uv.x + (noise(px * vec2(0.01, 0.2) + time * 0.7) - 0.5) * 0.006, 2.0 * my - uv.y);
            c += texture(fw, rq).rgb * water * 0.5;
        }
    }

    // ── lightning ──
    c += vec3(0.85, 0.9, 1.0) * flash * (sky * 0.9 + 0.2);

    // ── fog banks ──
    float wisp = 0.0;
    float fa = fog > 0.001 ? fogAmount(uv, sa, dist, wisp) : 0.0;
    c = mix(c, fogCol, fa);
    c = mix(c, fogCol * 1.05, wisp * 0.3);

    // ── falling rain at real depths ──
    if (rain > 0.0) {
        // streaks catch the light around them: plain sky-grey, brighter near lamps
        vec3 sc = fogCol * 1.25 + WARM * glow / 12.8 * lightsOn * 0.8 + vec3(0.03);
        float r = 0.0;
        r += rainStreaks(px, 5.0, 130.0, 24.0, 0.5, 520.0, 0.7 * rain, 31.0) * 0.40 * step(0.55, dist);
        r += rainStreaks(px, 9.0, 230.0, 58.0, 0.7, 900.0, 0.7 * rain, 7.0) * 0.50 * step(0.32, dist);
        r += rainStreaks(px, 19.0, 440.0, 150.0, 1.0, 1600.0, 0.6 * rain, 3.0) * 0.42 * step(0.14, dist);
        r += rainStreaks(px, 53.0, 900.0, 380.0, 2.4, 2600.0, 0.45 * rain, 1.0) * 0.16;
        c = mix(c, sc, clamp(r, 0.0, 0.8));
        // distant curtains of rain drifting through
        vec2 q = vec2(uv.x * sa + uv.y * windX * 0.3, uv.y);
        float curtain = fbm(vec2(q.x * 4.0 + time * 0.08 * windX, q.y * 0.7 - time * 0.9));
        c = mix(c, fogCol, rain * pow(dist, 1.5) * (0.12 + 0.35 * smoothstep(0.35, 0.75, curtain)));
        // splashes on the ground
        if (ground > 0.4 && up > 0.25)
            c = mix(c, sc * 1.05, splashes(px, near, 1.6 + rain) * rain * ground * smoothstep(0.4, 0.8, up) * 0.35);
    }

    // ── falling snow at real depths ──
    if (snowing > 0.0) {
        vec3 fc = vec3(0.93, 0.95, 1.0) * max(luma(fogCol) * 1.35, 0.25) + WARM * glow / 12.8 * lightsOn * 0.5;
        float s = 0.0;
        s += snowFlakes(px, 13.0, 0.7, 0.5, 26.0, 0.55 * snowing, 41.0) * 0.45 * step(0.6, dist);
        s += snowFlakes(px, 24.0, 1.2, 0.6, 42.0, 0.55 * snowing, 23.0) * 0.65 * step(0.35, dist);
        s += snowFlakes(px, 48.0, 2.2, 0.9, 70.0, 0.5 * snowing, 9.0) * 0.8 * step(0.15, dist);
        s += snowFlakes(px, 150.0, 7.0, 5.0, 120.0, 0.45 * snowing, 2.0) * 0.35;
        c = mix(c, fc, clamp(s, 0.0, 1.0));
        c = mix(c, fogCol, snowing * 0.15 * pow(dist, 1.3));                 // snow haze
    }

    // ── camera: soft vignette and a little grain ──
    vec2 vq = (uv - 0.5) * vec2(sa / 2.2, 1.0);
    c *= 1.0 - smoothstep(0.4, 1.0, length(vq)) * 0.35;
    c += (hash(uv * resolution + fract(time) * 100.0) - 0.5) * 0.018;

    fragColor = vec4(c, 1.0) * qt_Opacity;
}
