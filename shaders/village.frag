#version 440
// Midground: a Bavarian-style village street (Leavenworth-ish) seen from the
// patio. Back row of conifers, timber-framed houses with steep gables and
// balconies, street lamps, and the street itself. Snow builds up on roofs,
// sills, balconies, trees and ground; rain makes the street dark and glossy
// with rippling puddles that reflect the houses and lights. Holiday lights
// and decorations come from the holiday uniform and palette.
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
    vec3 pal1;          // holiday light colours
    vec3 pal2;
    vec3 pal3;
    float time;
    float lightsOn;     // 0 day .. 1 night
    float snow;         // 0 .. 1 snow depth on the ground (1 ≈ 40 cm)
    float wetness;      // 0 .. 1
    float rain;         // 0 .. 1, falling right now
    float windAmt;      // 0 .. 1
    float fog;          // 0 .. 1
    float flash;        // lightning
    float coverage;     // cloud cover 0 .. 1
    float holiday;      // 0 none, 1 christmas, 2 halloween, 3 july4, 4 newyear, 5 valentine,
                        // 6 stpatrick, 7 easter, 8 oktoberfest, 9 thanksgiving
};

//#include common.glsl

const float STREET = 0.80;          // where house fronts meet the street
const vec3 WARM = vec3(1.0, 0.62, 0.30);
const vec3 SNOW = vec3(0.90, 0.93, 0.97);
float PX;

float box(vec2 p, vec2 lo, vec2 hi) {
    vec2 a = smoothstep(lo - PX, lo + PX, p) * smoothstep(hi + PX, hi - PX, p);
    return a.x * a.y;
}
vec3 palette(float k) {
    float m = mod(k, 3.0);
    return m < 1.0 ? pal1 : (m < 2.0 ? pal2 : pal3);
}
vec4 over(vec4 top, vec4 bot) { return top + bot * (1.0 - top.a); }

vec3 ambient() {
    vec3 a = zenCol * 0.6 + vec3(0.012, 0.014, 0.022);
    a = mix(a, vec3(dot(a, vec3(0.333))), coverage * 0.7);
    return a + vec3(0.8, 0.85, 1.0) * flash * 0.6;
}
float sunAmt() { return max(sunDir.y, 0.0) * (1.0 - coverage * 0.8); }

// Street lamps, one every LAMP across the street
const float LAMP = 0.62;
vec2 lampPos(float k) { return vec2((k + 0.5) * LAMP + 0.08, STREET + 0.012); }
vec3 lampLight(vec2 q) {
    float k = floor((q.x - 0.08) / LAMP);
    vec3 l = vec3(0.0);
    for (int j = 0; j <= 1; j++) {
        vec2 lp = lampPos(k + float(j)) - vec2(0.0, 0.092);    // the lantern
        float d = length((q - lp) * vec2(1.0, 1.3));
        l += WARM * lightsOn * 0.55 * exp(-d / 0.07);
    }
    return l;
}

vec4 trees(vec2 q, vec3 L) {
    const float CW = 0.07;
    float i = floor(q.x / CW);
    float h1 = hash(vec2(i, 1.7)), h2 = hash(vec2(i, 8.3));
    if (h1 < 0.12) return vec4(0.0);
    float base = STREET - 0.018 - h2 * 0.012;
    float hgt = 0.11 + 0.11 * h1;
    float top = base - hgt;
    if (q.y < top - 0.01 || q.y > base + 0.002) return vec4(0.0);
    float t = clamp((q.y - top) / hgt, 0.0, 1.0);       // 0 top .. 1 base
    float cx = (i + 0.5) * CW + (h2 - 0.5) * 0.02;
    float sway = sin(time * (0.7 + h1 * 0.6) + i * 2.3) * windAmt * 0.005 * (1.0 - t);
    float lx = abs(q.x - cx - sway);
    float tier = fract(t * 3.4);
    float w = (0.008 + 0.034 * t) * (0.5 + 0.5 * tier) * (1.0 + 0.15 * (noise(vec2(q.y * 400.0, i)) - 0.5));
    float inside = smoothstep(w + PX, w - PX, lx) * step(top, q.y) * step(q.y, base - 0.008);
    float trunk = box(q, vec2(cx - 0.0025, base - 0.012), vec2(cx + 0.0025, base));
    float a = max(inside, trunk);
    if (a < 0.001) return vec4(0.0);

    vec3 c = vec3(0.035, 0.075, 0.05) * (0.75 + 0.5 * noise(q * vec2(350.0, 150.0)));
    // snow rests on the top of each tier, more where branches are flatter
    float rest = smoothstep(0.45, 0.0, tier) * (0.5 + 0.5 * noise(q * vec2(500.0, 260.0)));
    float sn = clamp(snow * 2.2 * rest + snow * 0.3, 0.0, 1.0) * step(0.02, snow);
    c = mix(c, SNOW, sn);
    c = mix(c, vec3(0.10, 0.07, 0.045), trunk * (1.0 - inside));
    c *= L;
    return vec4(c * a, a);
}

// Leavenworth's big lit town tree (Christmas only)
vec4 townTree(vec2 q, vec3 L, float aspect) {
    float cx = aspect * 0.5 + 0.15;
    float base = STREET + 0.006, hgt = 0.24, top = base - hgt;
    if (q.y < top - 0.02 || q.y > base || abs(q.x - cx) > 0.09) return vec4(0.0);
    float t = clamp((q.y - top) / hgt, 0.0, 1.0);
    float tier = fract(t * 4.0);
    float w = (0.006 + 0.075 * t) * (0.55 + 0.45 * tier);
    float inside = smoothstep(w + PX, w - PX, abs(q.x - cx)) * step(top, q.y);
    vec3 c = vec3(0.03, 0.08, 0.05) * L;
    c = mix(c, SNOW * L, clamp(snow * 2.0 * smoothstep(0.4, 0.0, tier), 0.0, 1.0));
    // bulbs scattered over the tree, twinkling slowly
    vec2 g = q * vec2(260.0, 260.0);
    vec2 cell = floor(g);
    float h = hash(cell + 3.0);
    float bulb = step(0.55, h) * smoothstep(0.32, 0.12, length(fract(g) - 0.5)) * inside;
    float tw = 0.65 + 0.35 * sin(time * (0.8 + h * 1.5) + h * 40.0);
    c += palette(floor(h * 30.0)) * bulb * tw * (0.6 + lightsOn * 1.4);
    // star on top
    float star = smoothstep(0.009, 0.003, length(q - vec2(cx, top - 0.004)));
    c += vec3(1.0, 0.85, 0.45) * star * 2.0;
    float a = max(inside, star);
    vec3 halo = WARM * lightsOn * 0.12 * exp(-length(q - vec2(cx, top + hgt * 0.55)) / 0.07);
    return vec4(c * a + halo, a);
}

vec4 houses(vec2 q, vec3 Lbase) {
    const float CW = 0.36;
    float i = floor(q.x / CW);
    float h1 = hash(vec2(i, 3.3)), h2 = hash(vec2(i, 5.9)), h3 = hash(vec2(i, 7.1));
    float hw = CW * (0.24 + 0.2 * h1);
    float cx = (i + 0.5) * CW + (h2 - 0.5) * (CW - 2.0 * hw - 0.02);
    float base = STREET - h3 * 0.006;
    float wallH = 0.075 + 0.07 * h2;
    float roofH = hw * (0.85 + 0.3 * h3);
    float wallTop = base - wallH;
    float lx = q.x - cx, alx = abs(lx);
    float ov = hw * 0.22;
    float roofLine = wallTop - roofH + alx * roofH / hw;   // underside of the roof edge
    const float FASCIA = 0.011;
    float snowT = snow * 0.022 * (0.85 + 0.3 * noise(vec2(q.x * 150.0, i)));

    float wall = box(q, vec2(cx - hw, wallTop), vec2(cx + hw, base));
    float gable = step(alx, hw) * smoothstep(roofLine - PX, roofLine + PX, q.y) * step(q.y, wallTop + PX);
    float inRoofX = step(alx, hw + ov);
    float roof = inRoofX * smoothstep(roofLine - FASCIA - PX, roofLine - FASCIA + PX, q.y)
                         * smoothstep(roofLine + PX, roofLine - PX, q.y);
    float roofSnow = inRoofX * step(0.02, snow)
                   * smoothstep(roofLine - FASCIA - snowT - PX, roofLine - FASCIA - snowT + PX, q.y)
                   * step(q.y, roofLine - FASCIA + PX);
    // chimney on some houses
    float chx = cx + hw * 0.45 * (h1 > 0.5 ? 1.0 : -1.0);
    float chTop = wallTop - roofH + abs(chx - cx) * roofH / hw - FASCIA - 0.03;
    float chim = step(0.35, h3) * box(q, vec2(chx - 0.008, chTop), vec2(chx + 0.008, chTop + 0.04));
    float chimSnow = chim * step(0.02, snow) * step(q.y, chTop + snowT * 0.6);
    float solid = max(max(max(wall, gable), max(roof, roofSnow)), chim);
    if (solid < 0.001) return vec4(0.0);
    vec3 L = Lbase;

    // plaster, timber, stone
    float hc4 = hash(vec2(i, 11.7));
    vec3 plaster = hc4 < 0.3 ? vec3(0.90, 0.88, 0.82)          // white
                 : hc4 < 0.5 ? vec3(0.94, 0.84, 0.58)          // butter yellow
                 : hc4 < 0.65 ? vec3(0.78, 0.86, 0.80)         // sage
                 : hc4 < 0.8 ? vec3(0.92, 0.78, 0.72)          // pale rose
                 : vec3(0.80, 0.84, 0.90);                     // pale blue
    vec3 timber = vec3(0.20, 0.12, 0.07);
    vec3 c = plaster * (0.9 + 0.12 * noise(q * vec2(500.0, 500.0)));

    // ground floor: stone
    float stone = step(base - wallH * 0.38, q.y) * wall;
    vec3 stoneCol = vec3(0.45, 0.43, 0.40) * (0.75 + 0.35 * noise(floor(q * vec2(180.0, 300.0))));
    c = mix(c, stoneCol, stone);

    // half-timbering on the upper floor and gable
    float upper = (1.0 - stone) * max(wall, gable);
    float tv = step(abs(fract(lx / (hw * 0.5) + 0.5) - 0.5) * hw * 0.5, 0.0016);
    float th = step(abs(q.y - wallTop), 0.0018) + step(abs(q.y - (base - wallH * 0.38)), 0.0018);
    float diag = step(abs(fract((lx + (q.y - wallTop)) / (hw * 0.5)) - 0.5) * hw * 0.5, 0.0013) * gable;
    c = mix(c, timber, clamp((tv + th + diag) * upper, 0.0, 1.0));

    // balcony across the upper floor
    float balY = base - wallH * 0.40;
    float balcony = box(q, vec2(cx - hw - 0.004, balY - 0.014), vec2(cx + hw + 0.004, balY));
    float slat = step(0.5, fract(q.x * 220.0));
    c = mix(c, timber * (0.8 + 0.4 * slat), balcony);
    float balSnow = step(0.02, snow) * box(q, vec2(cx - hw - 0.004, balY - 0.014 - snowT * 0.4), vec2(cx + hw + 0.004, balY - 0.014));

    // windows: 4 columns × 2 floors, plus one in the gable
    vec3 emit = vec3(0.0);
    float row = q.y < balY ? 0.0 : 1.0;
    float wy = row < 0.5 ? wallTop + (balY - 0.014 - wallTop) * 0.5 : base - wallH * 0.2;
    float k = clamp(floor((lx / hw + 0.8) / 0.4 + 0.5), 0.0, 4.0);
    float wxl = -0.8 + 0.4 * k;
    bool isDoor = row > 0.5 && k == 2.0;
    float wx = cx + wxl * hw;
    vec2 wsz = vec2(0.0075, 0.010);
    // gable window
    if (q.y < wallTop) { wx = cx; wy = wallTop - roofH * 0.38; k = 7.0; row = 2.0; }
    float win = isDoor ? 0.0 : box(q, vec2(wx - wsz.x, wy - wsz.y), vec2(wx + wsz.x, wy + wsz.y)) * max(wall, gable);
    float shutter = isDoor ? 0.0 : (box(q, vec2(wx - wsz.x * 2.0, wy - wsz.y), vec2(wx - wsz.x - 0.001, wy + wsz.y))
                                  + box(q, vec2(wx + wsz.x + 0.001, wy - wsz.y), vec2(wx + wsz.x * 2.0, wy + wsz.y)));
    vec3 shutterCol = mix(vec3(0.12, 0.28, 0.16), vec3(0.45, 0.10, 0.08), step(0.5, h3));
    c = mix(c, shutterCol, clamp(shutter, 0.0, 1.0) * max(wall, gable));
    // lights go on and off through the evening
    float litH = hash(vec2(i * 13.0 + k, row + floor(time / 900.0) * 7.0));
    float lit = step(0.3, litH) * lightsOn;
    vec2 wl = (q - vec2(wx, wy)) / wsz;
    float mull = step(abs(wl.x), 0.08) + step(abs(wl.y), 0.08);
    vec3 glass = mix(horCol * 0.35, WARM * (1.1 - 0.4 * wl.y) * (0.8 + 0.4 * litH), lit);
    c = mix(c, mix(glass, timber * 0.5, clamp(mull, 0.0, 1.0)), win);
    emit += glass * win * lit * 0.6;
    float sill = step(0.02, snow) * box(q, vec2(wx - wsz.x * 1.3, wy + wsz.y), vec2(wx + wsz.x * 1.3, wy + wsz.y + 0.002 + snow * 0.003));
    // warm spill around lit windows
    vec2 dw = (q - vec2(wx, wy)) / vec2(0.03, 0.025);
    vec3 spill = WARM * lit * 0.35 * exp(-dot(dw, dw));

    // door, with a lantern (and holiday decoration)
    float door = isDoor ? box(q, vec2(cx - 0.009, base - 0.032), vec2(cx + 0.009, base)) : 0.0;
    c = mix(c, timber * 0.8, door);
    vec2 lan = vec2(cx + 0.016, base - 0.036);
    float lanD = length(q - lan);
    emit += WARM * lightsOn * (smoothstep(0.0035, 0.002, lanD) * 1.5);
    spill += WARM * lightsOn * 0.5 * exp(-lanD / 0.018);
    if (holiday == 1.0 && isDoor) {           // wreath
        float r = length((q - vec2(cx, base - 0.022)) * vec2(1.0, 1.0));
        float ring = smoothstep(0.0025, 0.0015, abs(r - 0.006));
        c = mix(c, vec3(0.05, 0.22, 0.08), ring);
        float berries = ring * step(0.8, fract(atan(q.y - base + 0.022, q.x - cx) * 2.0));
        c = mix(c, vec3(0.7, 0.05, 0.05), berries);              // red bow / berries
    }

    // roof shingles, roof snow, chimney
    vec3 roofCol = mix(vec3(0.22, 0.09, 0.06), vec3(0.16, 0.15, 0.15), step(0.55, h1));
    roofCol *= 0.8 + 0.3 * step(0.5, fract(q.x * 260.0 + floor(q.y * 400.0) * 0.5));
    c = mix(c, roofCol, roof * (1.0 - gable));
    c = mix(c, vec3(0.42, 0.36, 0.33), chim);
    float anySnow = clamp(roofSnow + chimSnow + balSnow + sill, 0.0, 1.0);
    c = mix(c, SNOW * (0.92 + 0.1 * noise(q * 600.0)), anySnow);

    // light: sky + sun (fronts face north, so the sun mostly hits roofs and snow)
    float topLit = clamp(roof + anySnow, 0.0, 1.0);
    vec3 light = L * 1.6 + sunCol * sunAmt() * mix(0.30, 0.75, topLit) + spill;
    c *= light;
    c += emit;

    // holiday lights along the eaves
    float onEave = inRoofX * smoothstep(0.0035, 0.0012, abs(q.y - roofLine - 0.0015));
    float bulbs = step(0.5, holiday) * onEave * smoothstep(0.32, 0.12, abs(fract(q.x / 0.0075) - 0.5));
    vec3 hc = palette(floor(q.x / 0.0075));
    vec3 eaveGlow = hc * bulbs * (0.5 + 1.6 * lightsOn);
    c = mix(c, eaveGlow, bulbs * 0.85);
    float a = max(solid, bulbs);
    vec3 halo = step(0.5, holiday) * lightsOn * inRoofX * 0.12 * hc * exp(-abs(q.y - roofLine) / 0.006);

    // jack-o'-lanterns on the step
    if (holiday == 2.0) {
        vec2 jp = vec2(cx - 0.02, base - 0.004);
        float jd = length((q - jp) * vec2(1.0, 1.25));
        float pumpkin = smoothstep(0.0055, 0.0045, jd);
        vec3 pc = vec3(0.85, 0.38, 0.05) * light * 0.8;
        float face = step(abs(q.y - jp.y + 0.0005), 0.0012) * step(abs(q.x - jp.x), 0.003) + step(length(q - jp + vec2(0.0018, 0.0022)), 0.001) + step(length(q - jp + vec2(-0.0018, 0.0022)), 0.001);
        pc = mix(pc, vec3(1.0, 0.7, 0.2) * (0.6 + lightsOn), clamp(face, 0.0, 1.0));
        c = mix(c, pc, pumpkin);
        a = max(a, pumpkin);
        halo += vec3(1.0, 0.5, 0.1) * lightsOn * 0.25 * exp(-jd / 0.012);
    }
    return vec4(c * a + halo, a);
}

vec4 lamps(vec2 q, vec3 L) {
    float k = floor((q.x - 0.08) / LAMP + 0.5);
    vec2 lp = lampPos(k);
    float pole = box(q, vec2(lp.x - 0.002, lp.y - 0.085), vec2(lp.x + 0.002, lp.y));
    vec2 head = lp - vec2(0.0, 0.092);
    float lantern = box(q, head - vec2(0.007, 0.01), head + vec2(0.007, 0.01));
    float cap = box(q, head - vec2(0.009, 0.0135), head + vec2(0.009, -0.0085));
    float capSnow = step(0.02, snow) * box(q, head - vec2(0.0062, 0.0085 + snow * 0.004), head + vec2(0.0062, -0.0085));
    vec3 c = vec3(0.03) * L;
    c = mix(c, mix(vec3(0.25, 0.25, 0.22) * L, vec3(1.0, 0.82, 0.5) * 1.6, lightsOn), lantern);
    c = mix(c, SNOW * L * 1.2, capSnow);
    float a = clamp(pole + lantern + cap + capSnow, 0.0, 1.0);
    float d = length(q - head);
    vec3 halo = WARM * lightsOn * (exp(-d / 0.015) * 0.7 + exp(-d / 0.07) * 0.18);
    return vec4(c * a + halo, a);
}

vec4 village(vec2 q, float aspect) {
    vec3 L = ambient() + lampLight(q);
    vec4 o = trees(q, L + sunCol * sunAmt() * 0.4);
    if (holiday == 1.0) o = over(townTree(q, L + sunCol * sunAmt() * 0.4, aspect), o);
    o = over(houses(q, L), o);
    o = over(lamps(q, L), o);
    return o;
}

// Expanding rain rings on puddles: returns a small offset for the reflection
vec2 ripple(vec2 g) {
    vec2 off = vec2(0.0);
    for (int l = 0; l < 2; l++) {
        vec2 gg = g * (6.0 + float(l) * 3.0);
        vec2 cell = floor(gg);
        vec2 f = fract(gg) - 0.5 - (vec2(hash(cell), hash(cell + 9.1)) - 0.5) * 0.5;
        float t = fract(time * (0.9 + hash(cell + 2.0) * 0.6) + hash(cell + 5.0));
        float r = length(f);
        float wave = sin((r - t * 0.45) * 70.0) * smoothstep(0.45 * t + 0.08, 0.45 * t, r) * (1.0 - t);
        off += normalize(f + 1e-4) * wave;
    }
    return off * 0.0022 * rain;
}

void main() {
    vec2 uv = qt_TexCoord0;
    PX = 1.0 / resolution.y;
    float aspect = resolution.x / resolution.y;
    vec2 q = vec2(uv.x * aspect, uv.y);
    float hy = horizonY();
    vec3 fogCol = mix(horCol, vec3(dot(horCol, vec3(0.333))), coverage * 0.75) * 1.02;

    vec4 o = vec4(0.0);
    if (q.y < STREET + 0.002) {
        o = village(q, aspect);
    }
    if (q.y >= STREET - 0.004) {
        // ── the street ──
        float gz = max(q.y - hy, 1e-3);
        vec2 g = vec2((q.x - aspect * 0.5) / gz, 1.0 / gz) * 0.03;
        vec3 L = ambient() * 1.7 + vec3(0.01);      // the street faces the whole sky
        // lamp pools on the ground (ellipses in perspective)
        vec3 pools = vec3(0.0);
        float lk = floor((q.x - 0.08) / LAMP);
        for (int j = 0; j <= 1; j++) {
            vec2 lp = lampPos(lk + float(j));
            vec2 d = (q - vec2(lp.x, lp.y + 0.02)) / vec2(0.12, 0.035);
            pools += WARM * lightsOn * 0.9 * exp(-dot(d, d));
        }
        float curb = step(q.y, STREET + 0.010);
        vec3 ground = mix(vec3(0.17, 0.165, 0.16), vec3(0.42, 0.40, 0.37), curb);
        // cobbles
        vec2 cb = g * vec2(14.0, 14.0);
        float cob = smoothstep(0.42, 0.5, max(abs(fract(cb.x + 0.5 * floor(cb.y)) - 0.5), abs(fract(cb.y) - 0.5)));
        ground *= (0.85 + 0.25 * noise(floor(cb) * 1.7)) * (1.0 - cob * 0.35 * (1.0 - curb));
        vec3 lightG = L + sunCol * sunAmt() * 0.6 + pools;

        // wet and puddles
        float pTh = mix(0.80, 0.52, wetness);
        float puddle = smoothstep(pTh, pTh + 0.04, fbm(g * 1.2 + 3.1)) * step(0.15, wetness) * (1.0 - curb);
        float snowCover = smoothstep(0.0, 0.12, snow);
        puddle *= 1.0 - snowCover;
        vec3 c = ground * lightG * mix(1.0, 0.5, wetness * (1.0 - snowCover));

        // reflection: mirror the village about the street line
        float refl = puddle * 0.85 + wetness * (1.0 - puddle) * 0.28 * (1.0 - snowCover);
        if (refl > 0.01) {
            vec2 rq = vec2(q.x, 2.0 * STREET - q.y) + ripple(g) + vec2(0.0, (1.0 - puddle) * 0.004 * noise(g * 30.0));
            vec4 rv = village(rq, aspect);
            vec3 skyR = mix(horCol, zenCol, clamp((STREET - rq.y) / 0.35, 0.0, 1.0)) * 0.9;
            skyR = mix(skyR, fogCol, coverage * 0.6);
            vec3 rc = rv.rgb + skyR * (1.0 - rv.a);
            float fres = 0.55 + 0.45 * smoothstep(0.3, 0.0, q.y - STREET);
            c = mix(c, rc * 0.9, refl * fres);
        }

        // snow on the street, with lamp-lit sparkle
        vec3 snowCol = SNOW * (0.9 + 0.1 * noise(g * 40.0)) * (lightG * 1.1);
        float sparkle = step(0.997, hash(floor(q * resolution.y * 0.5))) * (lightsOn * 0.8 + sunAmt());
        snowCol += sparkle;
        c = mix(c, snowCol, snowCover * (0.85 + 0.15 * noise(g * 8.0)));

        float ga = smoothstep(STREET - 0.004, STREET + PX, q.y);
        o = vec4(mix(o.rgb, c, ga), max(o.a, ga));
    }

    // fog swallows the village before the patio
    float f = clamp(fog * 0.65, 0.0, 1.0);
    o.rgb = mix(o.rgb, fogCol * o.a, f);

    fragColor = o * qt_Opacity;
}
