// Shared camera + noise helpers. Included by sky.frag and clouds.frag via build.sh
// (qsb has no #include, so the build script pastes this in).

#define PI 3.14159265
#define PITCH 0.205     // camera tilted up ~12 deg, puts the horizon ~68% down the screen
#define TH 0.5774       // tan(30 deg): half the vertical field of view

// World: +y up, +z = south (the way the camera faces), +x = west (screen right)
vec3 rayDir(vec2 uv) {
    float aspect = resolution.x / resolution.y;
    vec2 ndc = vec2((uv.x - 0.5) * 2.0 * aspect, (0.5 - uv.y) * 2.0) * TH;
    vec3 fwd = vec3(0.0, sin(PITCH), cos(PITCH));
    vec3 up  = vec3(0.0, cos(PITCH), -sin(PITCH));
    return normalize(fwd + vec3(1.0, 0.0, 0.0) * ndc.x + up * ndc.y);
}

float horizonY() { return 0.5 + tan(PITCH) / (2.0 * TH); }

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = m * p; a *= 0.5; }
    return v;
}

float ridge(float x, float seed) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        float n = noise(vec2(x, seed));
        v += a * (1.0 - abs(n * 2.0 - 1.0));    // ridged: sharper peaks
        x *= 2.1; a *= 0.5;
    }
    return v;
}

// Top edge of the mountain range (screen y) at aspect-scaled x
float mountainTop(float ax) {
    float mx = ax * 0.55 + 4.0;
    return horizonY() - 0.03 - 0.30 * ridge(mx, 1.9) * (0.6 + 0.4 * noise(vec2(mx * 0.4, 5.0)));
}
