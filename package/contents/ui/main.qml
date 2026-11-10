/*
    Live Weather wallpaper: the view from a covered back patio. A physically
    based sky, perspective clouds, hills, sun/moon and stars (GPU shaders), with
    rain/snow/fog/lightning, all driven by Open-Meteo's current conditions and
    the real sun position for the configured location.
    SPDX-License-Identifier: GPL-3.0-or-later
*/
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Particles
import Qt.labs.folderlistmodel
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    // ── Settings ────────────────────────────────────────────────────────────
    readonly property real lat: configuration.Latitude
    readonly property real lon: configuration.Longitude
    readonly property bool fahrenheit: configuration.Fahrenheit
    readonly property bool showPatio: configuration.ShowPatio !== false
    readonly property bool photoMode: (configuration.SceneMode || "photos") === "photos"
    readonly property bool onlinePhotos: configuration.OnlinePhotos !== false
    readonly property bool liveSkyInPhotos: configuration.LiveSky !== false
    // Patio overlay: full patio for the drawn scene, just the string lights over photos
    readonly property string patioStyle: {
        const p = configuration.PatioStyle || "auto";
        if (!showPatio) return "off";
        if (p !== "auto") return p;
        if (!photoMode) return "full";
        // string lights belong in a back yard or a town, not over a wild mountain view
        return root.chosen && root.chosen.scene !== "wild" ? "lights" : "off";
    }
    // Which monitor this is (set by the Windows/macOS app), so each one gets its own view
    property int screenIndex: 0
    // Photos are decoded at screen size (+ room for the slow zoom), not their full
    // 3840 px. Tall enough to cover wide screens too (photos are 1.41:1 or wider),
    // but at most ~2600 real pixels high whatever the display scale.
    readonly property int decodeHeight: Math.ceil(Math.min(2600 / Math.max(1, Screen.devicePixelRatio),
                                                           Math.max(height, width / 1.41) * 1.15))
    readonly property string previewCondition: configuration.PreviewCondition || "auto"
    readonly property string previewTime: configuration.PreviewTime || "auto"
    readonly property string previewHoliday: configuration.PreviewHoliday || "auto"

    // ── Live weather ────────────────────────────────────────────────────────
    property bool loaded: false
    property int code: 2
    property real temp: NaN
    property real cloudCover: 50
    property real windMph: 3
    property real windDir: 270          // where the wind comes FROM, degrees
    property real snowDepthM: 0         // metres on the ground (model analysis)
    property real recentRain: 0         // mm in the last few hours, recent hours weighted more
    property date updated: new Date()
    property date now: new Date()

    readonly property var previewCodes: ({ clear: 0, partly: 2, cloudy: 3, fog: 45,
                                           rain: 63, snow: 73, storm: 95 })
    readonly property int effCode: previewCondition in previewCodes ? previewCodes[previewCondition] : code
    readonly property string kind: classify(effCode)
    readonly property real intensity: intensityOf(effCode)
    readonly property real effCloud: previewCondition === "auto" ? cloudCover
                                   : ({ clear: 0, partly: 40, cloudy: 100, fog: 100,
                                        rain: 100, snow: 100, storm: 100 })[previewCondition]
    readonly property real effWind: previewCondition === "auto" ? windMph
                                   : (kind === "storm" ? 22 : 6)

    function classify(c) {
        if (c <= 1) return "clear";
        if (c === 2) return "partly";
        if (c === 3) return "cloudy";
        if (c === 45 || c === 48) return "fog";
        if (c >= 51 && c <= 67) return "rain";
        if (c >= 71 && c <= 77) return "snow";
        if (c >= 80 && c <= 82) return "rain";
        if (c === 85 || c === 86) return "snow";
        if (c >= 95) return "storm";
        return "cloudy";
    }
    function intensityOf(c) {
        const t = { 51: .25, 53: .4, 55: .55, 56: .3, 57: .5,
                    61: .4, 63: .7, 65: 1, 66: .45, 67: .8,
                    71: .35, 73: .65, 75: 1, 77: .3,
                    80: .5, 81: .8, 82: 1, 85: .55, 86: 1,
                    95: .9, 96: 1, 99: 1 };
        return t[c] !== undefined ? t[c] : 0;
    }
    function describe(c) {
        const d = { 0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
                    45: "Fog", 48: "Freezing fog", 51: "Light drizzle", 53: "Drizzle",
                    55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
                    61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain",
                    67: "Freezing rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
                    77: "Snow grains", 80: "Rain showers", 81: "Rain showers",
                    82: "Violent showers", 85: "Snow showers", 86: "Heavy snow showers",
                    95: "Thunderstorm", 96: "Thunderstorm, hail", 99: "Thunderstorm, hail" };
        return d[c] || "";
    }
    function clamp(x) { return Math.max(0, Math.min(1, x)); }
    function smooth(a, b, x) { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); }

    // ── Sun and moon ────────────────────────────────────────────────────────
    // The time the scene shows: now, or a fixed time of day for the preview.
    readonly property date simTime: {
        const t = new Date(now);
        if (previewTime === "day")   t.setHours(12, 30, 0, 0);
        if (previewTime === "dusk")  t.setHours(16, 22, 0, 0);
        if (previewTime === "night") t.setHours(22, 30, 0, 0);
        return t;
    }

    // Low-precision solar position. Returns elevation and azimuth measured
    // from due south, positive toward the west (radians).
    function solar(date) {
        const rad = Math.PI / 180;
        const d = date.getTime() / 86400000 - 10957.5;          // days since J2000.0
        const g = (357.529 + 0.98560028 * d) * rad;
        const q = 280.459 + 0.98564736 * d;
        const L = (q + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * rad;
        const e = (23.439 - 0.00000036 * d) * rad;
        const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L));
        const dec = Math.asin(Math.sin(e) * Math.sin(L));
        const gmst = ((18.697374558 + 24.06570982441908 * d) % 24 + 24) % 24;
        const H = (gmst * 15 + lon) * rad - ra;                 // hour angle
        const la = lat * rad;
        const elev = Math.asin(Math.sin(la) * Math.sin(dec) + Math.cos(la) * Math.cos(dec) * Math.cos(H));
        const az = Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(la) - Math.tan(dec) * Math.cos(la));
        return { elev: elev, az: az };
    }
    // Screen direction for a sky object. The camera faces south and shows
    // roughly ±50°, so azimuth is squeezed to keep sunrise/sunset on screen,
    // and elevation is capped so the summer midday sun doesn't leave the top.
    function skyDir(elev, az) {
        const e = Math.min(elev, 38 * Math.PI / 180);
        const a = az * 0.62;
        return Qt.vector3d(Math.sin(a) * Math.cos(e), Math.sin(e), Math.cos(a) * Math.cos(e));
    }

    readonly property var sunPos: solar(simTime)
    readonly property vector3d sunDir: skyDir(sunPos.elev, sunPos.az)
    readonly property real nightness: smooth(0.02, -0.15, sunDir.y)

    // Moon: phase from the synodic month; placed on a gentle arc through the
    // night (a real ephemeris would put it in the daytime half the month).
    readonly property real moonPhase: {
        const days = (simTime.getTime() - Date.UTC(2000, 0, 6, 18, 14)) / 86400000;
        return ((days / 29.530588853) % 1 + 1) % 1;
    }
    readonly property vector3d moonDir: {
        const h = simTime.getHours() + simTime.getMinutes() / 60;
        const p = clamp(((h + 24 - 17) % 24) / 14);             // 17:00 → 07:00
        const elev = (6 + 30 * Math.sin(Math.PI * p)) * Math.PI / 180;
        const dir = skyDir(elev, (-0.8 + 1.6 * p) * 0.9);
        return nightness > 0.05 ? dir : Qt.vector3d(0, -1, 0);
    }

    // ── Holidays ────────────────────────────────────────────────────────────
    // Decorations go up ahead of each holiday, like people actually decorate.
    // Fireworks only on the night itself.
    readonly property var palettes: ({
        none:         [[1.0, 0.62, 0.28], [1.0, 0.66, 0.32], [1.0, 0.58, 0.25]],
        christmas:    [[1.0, 0.12, 0.08], [1.0, 0.72, 0.22], [0.12, 0.85, 0.25]],
        halloween:    [[1.0, 0.42, 0.04], [0.62, 0.22, 1.0], [1.0, 0.60, 0.10]],
        july4:        [[1.0, 0.10, 0.10], [1.0, 0.95, 0.90], [0.20, 0.35, 1.0]],
        valentine:    [[1.0, 0.10, 0.22], [1.0, 0.42, 0.70], [1.0, 0.78, 0.86]],
        stpatrick:    [[0.20, 1.0, 0.30], [0.75, 1.0, 0.70], [1.0, 0.75, 0.20]],
        easter:       [[1.0, 0.60, 0.80], [0.50, 0.75, 1.0], [1.0, 0.95, 0.50]],
        oktoberfest:  [[0.25, 0.50, 1.0], [1.0, 1.0, 1.0], [1.0, 0.70, 0.35]],
        thanksgiving: [[1.0, 0.55, 0.15], [1.0, 0.38, 0.08], [1.0, 0.72, 0.38]]
    })
    readonly property var holidayIds: ({ none: 0, christmas: 1, halloween: 2, july4: 3, newyear: 1,
                                         valentine: 5, stpatrick: 6, easter: 7, oktoberfest: 8, thanksgiving: 9 })

    function nthWeekday(y, month, weekday, n) {         // e.g. 4th Thursday of November
        const d = new Date(y, month, 1);
        const first = (weekday - d.getDay() + 7) % 7 + 1;
        return new Date(y, month, first + (n - 1) * 7);
    }
    function easterSunday(y) {                          // anonymous Gregorian algorithm
        const a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4;
        const f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
        const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1;
        return new Date(y, month - 1, day);
    }
    function holidayFor(t) {
        const y = t.getFullYear(), M = t.getMonth(), D = t.getDate(), H = t.getHours();
        const day = new Date(y, M, D);
        const DAY = 86400000;
        const within = (from, to) => day >= from && day <= to;
        const thanksgiving = nthWeekday(y, 10, 4, 4);
        const easter = easterSunday(y);
        // fireworks: the night of July 4, and New Year's Eve into the small hours
        const fireworks = (M === 6 && D === 4 && H >= 21) || (M === 6 && D === 5 && H < 1)
                       || (M === 11 && D === 31 && H >= 20) || (M === 0 && D === 1 && H < 2);
        let name = "none";
        if (M === 11 || (M === 0 && D <= 6) || day > thanksgiving) name = "christmas";
        else if (M === 10) name = "thanksgiving";        // harvest decorations all November
        else if (M === 9) {
            // Leavenworth Oktoberfest: the first three Fri–Sun weekends of October
            const fri = nthWeekday(y, 9, 5, 1);
            let okto = false;
            for (let w = 0; w < 3; w++) {
                const s0 = new Date(fri.getTime() + w * 7 * DAY);
                if (within(s0, new Date(s0.getTime() + 2 * DAY))) okto = true;
            }
            name = okto ? "oktoberfest" : "halloween";
        }
        else if (M === 6 && D <= 5) name = "july4";
        else if (M === 1 && D >= 7 && D <= 14) name = "valentine";
        else if (M === 2 && D >= 10 && D <= 17) name = "stpatrick";
        else if (within(new Date(easter.getTime() - 7 * DAY), easter)) name = "easter";
        return { name: name, fireworks: fireworks };
    }
    readonly property var holiday: {
        if (previewHoliday !== "auto") {
            const n = previewHoliday === "newyear" ? "christmas" : previewHoliday;
            return { name: n, fireworks: previewHoliday === "july4" || previewHoliday === "newyear" };
        }
        const decor = configuration.Decorations || "always";
        const h = holidayFor(simTime);
        if (decor === "off") return { name: "none", fireworks: h.fireworks };
        if (decor === "always" && h.name === "none") {
            // between holidays: the next one's decorations are already up
            for (let d = 1; d <= 120; d++) {
                const n = holidayFor(new Date(simTime.getTime() + d * 86400000)).name;
                if (n !== "none") return { name: n, fireworks: false };
            }
        }
        return h;
    }
    readonly property var pal: palettes[holiday.name] || palettes.none
    function palColor(k) { return Qt.vector3d(pal[k][0], pal[k][1], pal[k][2]); }

    // String light colours picked in the settings ("auto" follows the holiday palette)
    readonly property var lightColours: ({
        warm:   [1.0, 0.62, 0.28], white:  [0.85, 0.92, 1.0], red:    [1.0, 0.10, 0.08],
        orange: [1.0, 0.42, 0.06], yellow: [1.0, 0.82, 0.25], green:  [0.15, 0.95, 0.30],
        blue:   [0.20, 0.40, 1.0], purple: [0.62, 0.25, 1.0], pink:   [1.0, 0.40, 0.70]
    })
    readonly property string lightsColour: {
        const c = configuration.LightsColour || "auto";
        if (c !== "random") return c;
        // random: one choice per view, so it changes with the photo and not in between
        const opts = ["multi", "multi", "christmas", "july4", "halloween", "valentine", "easter",
                      "warm", "white", "red", "orange", "yellow", "green", "blue", "purple", "pink"];
        const key = chosenKey + (chosen ? chosen.name : "");
        let h = 7;
        for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
        return opts[h % opts.length];
    }
    function stringColour(k) {
        const c = lightsColour;
        const p = lightColours[c] ? [lightColours[c], lightColours[c], lightColours[c]]
                : palettes[c] ? palettes[c] : pal;               // auto / multi fall back to the holiday palette
        return Qt.vector3d(p[k][0], p[k][1], p[k][2]);
    }

    // ── Sky colours for lighting the clouds/ground (CPU copy of sky.frag) ───
    function atmosphere(r, s, isteps, jsteps) {
        const R0 = [0, 6372e3, 0], RP = 6371e3, RA = 6471e3;
        const kR = [5.5e-6, 13.0e-6, 22.4e-6], kM = 21e-6, shR = 8e3, shM = 1.2e3, g = 0.758;
        function rsi(o, d, sr) {
            const b = 2 * (o[0] * d[0] + o[1] * d[1] + o[2] * d[2]);
            const c = o[0] * o[0] + o[1] * o[1] + o[2] * o[2] - sr * sr;
            const disc = b * b - 4 * c;
            if (disc < 0) return [1e5, -1e5];
            return [(-b - Math.sqrt(disc)) / 2, (-b + Math.sqrt(disc)) / 2];
        }
        const p = rsi(R0, r, RA);
        if (p[0] > p[1]) return [0, 0, 0];
        p[1] = Math.min(p[1], rsi(R0, r, RP)[0]);
        const st = (p[1] - p[0]) / isteps;
        let t = 0, odR = 0, odM = 0;
        const tR = [0, 0, 0], tM = [0, 0, 0];
        const mu = r[0] * s[0] + r[1] * s[1] + r[2] * s[2], gg = g * g;
        const pR = 3 / (16 * Math.PI) * (1 + mu * mu);
        const pM = 3 / (8 * Math.PI) * ((1 - gg) * (mu * mu + 1)) / (Math.pow(1 + gg - 2 * mu * g, 1.5) * (2 + gg));
        for (let i = 0; i < isteps; i++) {
            const pos = [R0[0] + r[0] * (t + st / 2), R0[1] + r[1] * (t + st / 2), R0[2] + r[2] * (t + st / 2)];
            const hgt = Math.hypot(pos[0], pos[1], pos[2]) - RP;
            const dR = Math.exp(-hgt / shR) * st, dM = Math.exp(-hgt / shM) * st;
            odR += dR; odM += dM;
            const js = rsi(pos, s, RA)[1] / jsteps;
            let jt = 0, jR = 0, jM = 0;
            for (let j = 0; j < jsteps; j++) {
                const q = [pos[0] + s[0] * (jt + js / 2), pos[1] + s[1] * (jt + js / 2), pos[2] + s[2] * (jt + js / 2)];
                const jh = Math.hypot(q[0], q[1], q[2]) - RP;
                jR += Math.exp(-jh / shR) * js; jM += Math.exp(-jh / shM) * js;
                jt += js;
            }
            for (let c = 0; c < 3; c++) {
                const at = Math.exp(-(kM * (odM + jM) + kR[c] * (odR + jR)));
                tR[c] += dR * at; tM[c] += dM * at;
            }
            t += st;
        }
        return [0, 1, 2].map(c => 1 - Math.exp(-22 * (pR * kR[c] * tR[c] + pM * kM * tM[c])));
    }
    function sunTransmittance(s) {
        // optical depth from the viewer toward the sun
        const R0 = [0, 6372e3, 0], RP = 6371e3, RA = 6471e3, steps = 16;
        const b = 2 * R0[1] * s[1], c = R0[1] * R0[1] - RA * RA;
        const far = (-b + Math.sqrt(b * b - 4 * c)) / 2, st = far / steps;
        let odR = 0, odM = 0;
        for (let i = 0; i < steps; i++) {
            const tt = st * (i + 0.5);
            const hgt = Math.hypot(s[0] * tt, R0[1] + s[1] * tt, s[2] * tt) - RP;
            if (hgt < 0) return [0, 0, 0];
            odR += Math.exp(-hgt / 8e3) * st; odM += Math.exp(-hgt / 1.2e3) * st;
        }
        const kR = [5.5e-6, 13.0e-6, 22.4e-6];
        return kR.map(k => Math.exp(-(k * odR + 21e-6 * 1.1 * odM)));
    }
    function v3(a, gain) { return Qt.vector3d(a[0] * gain, a[1] * gain, a[2] * gain); }

    readonly property var skyColours: {
        const s = [sunDir.x, sunDir.y, sunDir.z];
        const zen = atmosphere([0, 1, 0], s, 10, 4);
        const hs = Math.hypot(s[0], s[2]) || 1;
        const towardSun = atmosphere([s[0] / hs * 0.999, 0.04, s[2] / hs * 0.999], s, 10, 4);
        const away = atmosphere([-s[0] / hs * 0.999, 0.04, -s[2] / hs * 0.999], s, 10, 4);
        // the camera looks south, so weight the horizon toward whatever is in front
        const front = atmosphere([0, 0.04, 0.999], s, 10, 4);
        const hor = [0, 1, 2].map(c => front[c] * 0.6 + (towardSun[c] + away[c]) * 0.2);
        const tr = sunTransmittance(s);
        const vis = smooth(-0.04, 0.03, s[1]);
        return { zen: v3(zen, 1), hor: v3(hor, 1), sun: v3(tr, vis) };
    }

    // ── Weather → scene parameters ──────────────────────────────────────────
    property real coverage: clamp(kind === "clear" ? effCloud / 100 * 0.35
                                : kind === "partly" ? 0.25 + effCloud / 100 * 0.3
                                : kind === "cloudy" ? 0.55 + effCloud / 100 * 0.45
                                : 1.0)
    property real darkness: kind === "storm" ? 0.9 : kind === "rain" ? 0.25 + intensity * 0.45
                          : kind === "snow" ? 0.25 : kind === "cloudy" ? 0.15 : 0
    property real fog: kind === "fog" ? 0.85 : kind === "rain" ? 0.12 + intensity * 0.2
                     : kind === "snow" ? 0.15 + intensity * 0.25 : kind === "storm" ? 0.3 : 0
    // Snow on the ground comes from the real snow depth; the preview fakes a good dump
    property real snowGround: previewCondition === "snow" ? 0.8
                            : previewCondition !== "auto" ? 0
                            : clamp(snowDepthM / 0.4)
    // Wet ground: raining now, or rain in the last few hours that hasn't dried yet
    property real wetness: snowGround > 0.3 ? 0
                         : (kind === "rain" || kind === "storm") ? Math.max(0.65 + intensity * 0.35, clamp(recentRain / 2))
                         : previewCondition !== "auto" ? 0 : clamp(recentRain / 2)
    // Peaks are white most of the year; the snowline drops in winter
    readonly property real mountainSnow: {
        const m = simTime.getMonth();                   // 0 = Jan
        const seasonal = [1, 1, 0.9, 0.75, 0.55, 0.35, 0.15, 0.1, 0.25, 0.5, 0.8, 1][m];
        return Math.max(seasonal, snowGround > 0.05 ? 1 : 0);
    }
    // Changes ease in slowly, except right after start-up or a preview switch
    property bool settled: false
    Timer { id: settle; interval: 4000; running: true; onTriggered: root.settled = true }
    Behavior on coverage { enabled: root.settled; NumberAnimation { duration: 15000; easing.type: Easing.InOutSine } }
    Behavior on darkness { enabled: root.settled; NumberAnimation { duration: 15000 } }
    Behavior on fog { enabled: root.settled || root.previewCondition === "fog"; NumberAnimation { duration: 20000; easing.type: Easing.InOutSine } }
    Behavior on snowGround { enabled: root.settled; NumberAnimation { duration: 60000 } }
    Behavior on wetness { enabled: root.settled; NumberAnimation { duration: 30000 } }

    // Wind: travel direction in world space (+x west, +z south)
    readonly property real windRad: windDir * Math.PI / 180
    readonly property real windX: Math.sin(windRad)     // + = blowing toward screen right (west)
    readonly property real windZ: Math.cos(windRad)
    property vector2d windOffset: Qt.vector2d(0, 0)
    property real clock: 0

    // Animation clock, deliberately capped: everything here moves slowly, so
    // 15 fps is plenty when it's calm and 30 fps when rain or snow is falling.
    // The shaders only redraw when this ticks, which keeps the GPU mostly idle.
    readonly property bool busy: kind === "rain" || kind === "storm" || kind === "snow"
                                 || (holiday.fireworks && nightness > 0.5)
    readonly property int fps: busy ? 30 : 15
    property real lastTick: Date.now()
    Timer {
        interval: Math.round(1000 / root.fps)
        running: true; repeat: true
        onTriggered: {
            const t = Date.now();
            const dt = Math.min(0.25, (t - root.lastTick) / 1000);   // don't jump after a pause
            root.lastTick = t;
            // calmer at night
            const speed = (0.006 + Math.min(root.effWind, 40) * 0.0016) * (1 - root.nightness * 0.45);
            root.windOffset = Qt.vector2d(root.windOffset.x - root.windX * speed * dt,
                                          root.windOffset.y - root.windZ * speed * dt);
            root.clock += dt;
        }
    }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer {
        interval: Math.max(5, root.configuration.RefreshMinutes) * 60000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.fetchWeather()
    }
    Timer { id: retry; interval: 120000; onTriggered: root.fetchWeather() }
    onLatChanged: fetchWeather()
    onLonChanged: fetchWeather()
    onFahrenheitChanged: fetchWeather()

    function fetchWeather() {
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
            + "&current=temperature_2m,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m"
            + "&hourly=snow_depth,precipitation&past_hours=6&forecast_hours=1"
            + "&timezone=auto&wind_speed_unit=mph" + (fahrenheit ? "&temperature_unit=fahrenheit" : "");
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try {
                if (xhr.status !== 200) throw new Error("HTTP " + xhr.status);
                const j = JSON.parse(xhr.responseText);
                root.code = j.current.weather_code;
                root.temp = j.current.temperature_2m;
                root.cloudCover = j.current.cloud_cover;
                root.windMph = j.current.wind_speed_10m;
                root.windDir = j.current.wind_direction_10m;
                const sd = j.hourly.snow_depth.filter(v => v !== null);
                root.snowDepthM = sd.length ? sd[sd.length - 1] : 0;
                const pr = j.hourly.precipitation;
                let wsum = 0;
                for (let k = 0; k < pr.length; k++)
                    wsum += (pr[k] || 0) * Math.pow(0.7, pr.length - 1 - k);
                root.recentRain = wsum;
                root.updated = new Date();
                root.now = new Date();
                root.loaded = true;
            } catch (e) {
                console.warn("weatherwall: weather fetch failed:", e);
                retry.restart();
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // ── Photo library ───────────────────────────────────────────────────────
    // Each photo is a folder "<bucket>__<name>" holding photo.jpg plus the
    // depth/segmentation maps from tools/analyze.py. Bundled photos live in the
    // package; tools/fetch_online.py adds fresh ones to ~/.local/share/weatherwall.
    readonly property var nightBuckets: ["clear_night", "snow_night", "rain_night", "christmas", "custom_night"]
    readonly property var snowyBuckets: ["snow_day", "snow_night", "christmas", "dusk_winter"]
    readonly property var duskBuckets: ["dusk", "dusk_winter"]

    FolderListModel {
        id: bundled
        folder: Qt.resolvedUrl("../photos")
        showFiles: false; showDirs: true; showDotAndDotDot: false
    }
    FolderListModel {
        id: online
        folder: root.homeDir ? "file://" + root.homeDir + "/.local/share/weatherwall/photos" : ""
        showFiles: false; showDirs: true; showDotAndDotDot: false
    }
    // StandardPaths isn't exposed to wallpapers; the package is installed
    // under ~/.local/share, so take the home folder from its path
    readonly property string homeDir: {
        const u = Qt.resolvedUrl(".").toString().replace("file://", "");
        const i = u.indexOf("/.local/share/");
        return i > 0 ? u.substring(0, i) : "";
    }

    readonly property var library: {
        const out = [];
        const add = (model) => {
            for (let i = 0; i < model.count; i++) {
                const name = model.get(i, "fileName");
                const url = model.get(i, "fileUrl").toString();
                // <bucket>__<scene>__<name>  (scene: wild, town or yard)
                const parts = name.split("__");
                if (parts.length >= 2)
                    out.push({ bucket: parts[0], scene: parts.length >= 3 ? parts[1] : "wild", url: url, name: name });
            }
        };
        bundled.count; online.count;                    // re-evaluate when folders load
        add(bundled);
        if (onlinePhotos) add(online);
        return out;
    }

    readonly property string timeBand: nightness > 0.6 ? "night"
                                     : (sunDir.y < 0.14 && sunDir.y > -0.09) ? "dusk" : "day"
    readonly property string season: {
        const m = simTime.getMonth(), d = simTime.getDate();
        if (m === 11 || m <= 1 || snowGround > 0.1) return "winter";
        if ((m === 8 && d >= 20) || m === 9 || (m === 10 && d < 25)) return "autumn";
        return "summer";
    }
    // Buckets to try, best match first
    readonly property var wantedBuckets: {
        const n = timeBand === "night", dk = timeBand === "dusk";
        const snowy = kind === "snow" || snowGround > 0.2;
        let w = [];
        if (holiday.name === "christmas" && (n || dk)) w.push("christmas", "snow_night");
        if (holiday.name === "halloween" && (n || dk)) w.push("halloween");
        if (kind === "fog") w.push("fog");
        if (kind === "storm") w.push(n ? "rain_night" : "storm");
        if (snowy) w = w.concat(n ? ["snow_night"] : dk ? ["dusk_winter", "snow_day"] : ["snow_day"]);
        if (kind === "rain" || kind === "storm") w = w.concat(n ? ["rain_night"] : ["rain_day", "cloudy_day"]);
        if (kind === "cloudy") w = w.concat(n ? [] : ["cloudy_day"]);
        if (n) w = w.concat(snowy ? ["snow_night", "clear_night"] : ["clear_night"]);
        else if (dk) w = w.concat(season === "winter" ? ["dusk_winter", "dusk"] : ["dusk"]);
        else w = w.concat(season === "autumn" ? ["autumn", "clear_day"] : season === "winter" ? ["snow_day", "clear_day"] : ["clear_day"]);
        // anything daytime can be relit as a last resort
        return w.concat(["clear_day", "cloudy_day", "snow_day"]);
    }
    // When the view changes:
    //   twice  - new view at sunrise and at sunset (a real night photo); weather never swaps it
    //   daily  - one view from sunrise to sunrise, darkened at night
    //   weather - a photo that matches each condition (swaps when the weather changes)
    readonly property string photoChange: configuration.PhotoChange || "twice"
    readonly property bool isNightPeriod: sunDir.y < -0.02
    // A key that changes only when a new view is due
    readonly property string periodKey: {
        // the "photo day" starts at sunrise, so the evening belongs to that day
        const t = new Date(simTime.getTime() - (isNightPeriod && simTime.getHours() < 12 ? 86400000 : 0));
        const day = t.getFullYear() + "-" + t.getMonth() + "-" + t.getDate();
        if (photoChange === "daily") return day;
        if (photoChange === "weather") return day + (isNightPeriod ? "n" : "d") + wantedBuckets.join();
        return day + (isNightPeriod ? "n" : "d");
    }
    // Places: mix, towns (towns and back yards), nature
    readonly property string places: configuration.Places || "mix"
    function placeOk(p) {
        return places === "mix" || (places === "towns" ? p.scene !== "wild" : p.scene === "wild");
    }
    function pickPhoto(buckets, key) {
        for (const b of buckets) {
            let list = library.filter(p => p.bucket === b && placeOk(p));
            if (holiday.fireworks && timeBand === "night") {
                const towns = list.filter(p => p.scene !== "wild");
                if (towns.length) list = towns;
            }
            if (!list.length && places !== "mix") continue;
            if (list.length) {
                let h = 2166136261;
                for (let i = 0; i < key.length; i++) h = ((h ^ key.charCodeAt(i)) * 16777619) >>> 0;
                return list[h % list.length];
            }
        }
        if (places !== "mix") {
            for (const b of buckets) {
                const list = library.filter(p => p.bucket === b);
                if (list.length) return list[key.length % list.length];
            }
        }
        return null;
    }
    // Buckets for the start of a period. In "daily" mode the night uses the
    // morning's daytime pick (relit), so only daytime buckets are considered.
    readonly property var periodBuckets: photoChange === "daily"
        ? wantedBuckets.filter(b => nightBuckets.indexOf(b) < 0).concat(["clear_day"])
        : wantedBuckets
    property var chosen: null
    property string chosenKey: ""
    // Your own photo, if chosen: always shown, everything else reacts to it
    readonly property bool useOwnPhoto: configuration.UseOwnPhoto === true && (configuration.OwnPhoto || "") !== ""
    readonly property var ownPhoto: {
        if (!useOwnPhoto) return null;
        const path = configuration.OwnPhoto;
        const parts = path.split("/").pop().split("__");
        return { bucket: parts[0], scene: parts.length >= 3 ? parts[1] : "wild", url: "file://" + path, name: parts.pop() };
    }
    onOwnPhotoChanged: { chosenKey = ""; choose(); }
    // Town views with open sky (tools/skyline.py): fireworks nights use these,
    // relit as night if they're daytime photos
    Loader { id: fwViewsBundled; source: Qt.resolvedUrl("../photos/FireworksViews.qml") }
    readonly property var fireworksViews: fwViewsBundled.item ? fwViewsBundled.item.names : []
    function choose() {
        if (ownPhoto) { chosen = ownPhoto; chosenKey = periodKey; return; }
        if (!library.length) return;
        if (chosenKey === periodKey && chosen) return;
        const key = periodKey + (screenIndex > 0 ? "#screen" + screenIndex : "");
        if (holiday.fireworks && isNightPeriod) {
            const list = library.filter(p => fireworksViews.indexOf(p.name) >= 0);
            if (list.length) {
                let h = 2166136261;
                for (let i = 0; i < key.length; i++) h = ((h ^ key.charCodeAt(i)) * 16777619) >>> 0;
                chosen = list[h % list.length];
                chosenKey = periodKey;
                return;
            }
        }
        chosen = pickPhoto(periodBuckets, key);
        chosenKey = periodKey;
    }
    onPeriodKeyChanged: choose()
    onLibraryChanged: choose()
    onFireworksViewsChanged: { chosenKey = ""; choose(); }
    onPreviewConditionChanged: { settled = false; settle.restart(); chosenKey = ""; choose(); }
    onPreviewTimeChanged: { chosenKey = ""; choose(); }
    onPreviewHolidayChanged: { chosenKey = ""; choose(); }
    onPhotoChangeChanged: { chosenKey = ""; choose(); }
    onPlacesChanged: { chosenKey = ""; choose(); }

    // Shared by the layers below
    readonly property real slowClock: clock
    readonly property bool fireworksOn: holiday.fireworks && nightness > 0.5
    property vector3d fwColour: Qt.vector3d(1, 1, 1)
    property real fwLevel: 0
    readonly property vector3d fwLight: Qt.vector3d(fwColour.x * fwLevel, fwColour.y * fwLevel, fwColour.z * fwLevel)
    NumberAnimation { id: fwFade; target: root; property: "fwLevel"; to: 0; duration: 2400; easing.type: Easing.OutCubic }

    // Everything you see, so the glass in front can bend it
    Item {
    id: sceneRoot
    anchors.fill: parent

    // ── Scene ───────────────────────────────────────────────────────────────
    // Sky + clouds. In photo mode they aren't shown directly; the photo
    // shader uses them as the live sky behind the photo's buildings and trees.
    Item {
    id: skyGroup
    anchors.fill: parent
    // Sky + hills: expensive but only changes when the sun moves, so it is
    // rendered into a cached layer.
    Item {
        anchors.fill: parent
        layer.enabled: true
        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("shaders/sky.frag.qsb")
            property vector2d resolution: Qt.vector2d(root.width, root.height)
            property vector3d sunDir: root.sunDir
            property vector3d sunCol: root.skyColours.sun
            property vector3d zenCol: root.skyColours.zen
            property vector3d horCol: root.skyColours.hor
            property vector3d moonDir: root.moonDir
            property real moonPhase: root.moonPhase
            property real snowGround: root.snowGround
            property real overcast: root.coverage
            property real fog: root.fog
            property real mountainSnow: root.mountainSnow
        }
    }

    // Clouds, haze and fog at half resolution (they are soft anyway)
    Item {
        width: Math.ceil(root.width / 2); height: Math.ceil(root.height / 2)
        scale: 2; transformOrigin: Item.TopLeft
        layer.enabled: true
        layer.smooth: true
        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("shaders/clouds.frag.qsb")
            property vector2d resolution: Qt.vector2d(root.width, root.height)
            property vector3d sunDir: root.sunDir
            property vector3d sunCol: root.skyColours.sun
            property vector3d zenCol: root.skyColours.zen
            property vector3d horCol: root.skyColours.hor
            property vector2d windOffset: root.windOffset
            property real coverage: root.coverage
            property real darkness: root.darkness
            property real time: root.clock
            property real fog: root.fog
            property real flash: flashLevel.value * 0.6
            property real cityGlow: root.nightness * root.coverage
        }
    }
    }
    ShaderEffectSource {
        id: liveSkyTex
        sourceItem: skyGroup
        hideSource: root.photoMode
        live: root.photoMode && photoView.skyMix > 0
        visible: false
        textureSize: Qt.size(Math.ceil(root.width / 2), Math.ceil(root.height / 2))
    }

    // ── Photo mode ──
    component PhotoLayer: ShaderEffect {
        id: layer
        property string folder: ""
        readonly property bool ready: imgPhoto.status === Image.Ready && imgMaps.status === Image.Ready
                                      && imgMaps2.status === Image.Ready && imgMaps3.status === Image.Ready
                                      && imgSky.status === Image.Ready
        anchors.fill: parent
        // decoded at screen size (+ room for the slow zoom), not the full 3840 px
        Image {
            id: imgPhoto
            source: layer.folder ? layer.folder + "/photo.jpg" : ""
            sourceSize.height: root.decodeHeight
            visible: false; asynchronous: true; smooth: true
        }
        Image { id: imgMaps; source: layer.folder ? layer.folder + "/maps.png" : ""; visible: false; asynchronous: true; smooth: true }
        Image { id: imgMaps2; source: layer.folder ? layer.folder + "/maps2.png" : ""; visible: false; asynchronous: true; smooth: true }
        Image { id: imgMaps3; source: layer.folder ? layer.folder + "/maps3.png" : ""; visible: false; asynchronous: true; smooth: true }
        Image { id: imgSky; source: layer.folder ? layer.folder + "/sky.png" : ""; visible: false; asynchronous: true; smooth: true }
        // holiday props (tools/props.py); photos without them get a blank one
        readonly property string propsName: root.holiday.name !== "none" ? root.holiday.name : ""
        Image {
            id: imgProps
            source: layer.folder && layer.propsName ? layer.folder + "/props_" + layer.propsName + ".png" : Qt.resolvedUrl("images/clear.png")
            visible: false; asynchronous: true; smooth: true
            onStatusChanged: if (status === Image.Error) source = Qt.resolvedUrl("images/clear.png")
        }
        Image {
            id: imgPropsGlow
            source: layer.folder && layer.propsName ? layer.folder + "/glow_" + layer.propsName + ".png" : Qt.resolvedUrl("images/blank.png")
            visible: false; asynchronous: true; smooth: true
            onStatusChanged: if (status === Image.Error) source = Qt.resolvedUrl("images/blank.png")
        }
        property variant props: imgProps
        property variant propsGlow: imgPropsGlow
        // holiday decorations (photos without any get a blank one)
        Image {
            id: imgDecor
            source: layer.folder ? layer.folder + "/decor.png" : ""
            sourceSize.height: root.decodeHeight
            visible: false; asynchronous: true; smooth: true
            onStatusChanged: if (status === Image.Error) source = Qt.resolvedUrl("images/blank.png")
        }
        fragmentShader: Qt.resolvedUrl("shaders/photo.frag.qsb")
        property variant photo: imgPhoto
        property variant maps: imgMaps
        property variant maps2: imgMaps2
        property variant maps3: imgMaps3
        property variant skyMask: imgSky
        property variant liveSky: liveSkyTex
        property variant decor: imgDecor
        property variant fw: fwTex
        property vector3d fwLight: root.fwLight
        property real fwOn: root.fireworksOn || root.fwLevel > 0 ? 1 : 0
        // where the open sky ends, per column (tools/skyline.py)
        Loader { id: skylineData; source: layer.folder ? layer.folder + "/Skyline.qml" : "" }
        readonly property var skyline: skylineData.item ? skylineData.item.y : null
        // photo coordinates (0..1) to screen fractions, matching the shader's fit + drift
        function toScreen(px, py) {
            const sa = root.width / root.height, pa = photoAspect;
            let fx = 0.5 + (px - pan.x - 0.5) * zoom, fy = 0.5 + (py - pan.y - 0.5) * zoom;
            if (pa > sa) fx = 0.5 + (fx - 0.5) * pa / sa;
            else fy = 0.5 + (fy - 0.5) * sa / pa;
            return Qt.point(fx, fy);
        }
        property vector3d pal1: root.palColor(0)
        property vector3d pal2: root.palColor(1)
        property vector3d pal3: root.palColor(2)
        property real decorOn: root.holiday.name !== "none" ? 1 : 0
        readonly property string bucket: folder ? folder.replace(/\/+$/, "").split("/").pop().split("__")[0] : ""
        readonly property bool isNight: root.nightBuckets.indexOf(bucket) >= 0
        readonly property bool isSnowy: root.snowyBuckets.indexOf(bucket) >= 0
        readonly property bool isDusk: root.duskBuckets.indexOf(bucket) >= 0
        readonly property bool sunnyPhoto: ["clear_day", "autumn", "dusk", "dusk_winter", "snow_day", "custom"].indexOf(bucket) >= 0
        property vector2d resolution: Qt.vector2d(root.width, root.height)
        property real photoAspect: imgPhoto.implicitWidth / Math.max(1, imgPhoto.implicitHeight)
        property real zoom: 1.05 + 0.035 * Math.sin(root.slowClock / 700)
        property vector2d pan: Qt.vector2d(0.012 * Math.sin(root.slowClock / 830), 0.006 * Math.cos(root.slowClock / 1100))
        property real time: root.slowClock
        property real relight: isNight ? 0 : root.nightness
        property real dusk: isDusk || isNight ? 0 : root.smooth(0.25, 0.02, root.sunDir.y) * (1 - root.nightness) * (1 - root.coverage * 0.7)
        property real lightsOn: root.smooth(0.06, -0.04, root.sunDir.y)
        property real snow: root.snowGround * (isSnowy ? 0.25 : 1)
        property real snowing: root.kind === "snow" ? Math.max(0.4, root.intensity) : 0
        property real wetness: root.wetness
        property real rain: (root.kind === "rain" || root.kind === "storm") ? Math.max(0.4, root.intensity) : 0
        property real fog: root.fog
        property real flash: flashLevel.value * 0.7
        property real windAmt: root.clamp(root.effWind / 25)
        property real windX: root.windX
        property real gloom: sunnyPhoto ? root.clamp((root.coverage - 0.45) / 0.5) : 0
        property real skyMix: root.liveSkyInPhotos && sunnyPhoto ? root.clamp((root.coverage - 0.35) / 0.4) * 0.9 : 0
        property vector3d fogCol: {
            const h = root.skyColours.hor, g = (h.x + h.y + h.z) / 3;
            const k = root.coverage * 0.75;
            // at night fog and rain haze catch the glow of nearby lights
            const n = root.nightness * (0.4 + root.fog);
            return Qt.vector3d(h.x + (g - h.x) * k + 0.05 * n, h.y + (g - h.y) * k + 0.043 * n, h.z + (g - h.z) * k + 0.038 * n);
        }
    }
    Item {
        id: photoView
        anchors.fill: parent
        visible: root.photoMode
        property bool aFront: true
        readonly property real skyMix: (aFront ? photoA : photoB).skyMix
        readonly property string want: root.chosen ? root.chosen.url : ""
        onWantChanged: {
            const back = aFront ? photoB : photoA;
            if (back.folder === want) { aFront = !aFront; return; }
            back.folder = want;
        }
        Component.onCompleted: { photoA.folder = want; }
        PhotoLayer {
            id: photoA
            opacity: photoView.aFront ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 3000; easing.type: Easing.InOutQuad } }
        }
        PhotoLayer {
            id: photoB
            opacity: photoView.aFront ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 3000; easing.type: Easing.InOutQuad } }
        }
        // switch to the newly loaded photo once all three images are in
        Connections {
            target: photoView.aFront ? photoB : photoA
            function onReadyChanged() {
                const back = photoView.aFront ? photoB : photoA;
                if (back.ready && back.folder === photoView.want) photoView.aFront = !photoView.aFront;
            }
        }
    }

    // ── Fireworks (holiday nights only) ────────────────────────────────────
    // Shells launch from behind the skyline on a glowing tail, break into stars
    // that slow quickly in the air, droop and burn out, and leave smoke drifting
    // on the wind. Each break lights up the town. In photo mode the photo
    // shader draws this layer, so it only shows in open sky (and in water).

    Item {
        id: fwLayer
        anchors.fill: parent
        ParticleSystem {
            id: fireworks
            anchors.fill: parent
            running: root.fireworksOn
            property var pending: []

            // the rising shell and the sparks falling off its tail
            ImageParticle { groups: ["shell"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ffe2b0" }
            ImageParticle { groups: ["tail"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ff9a3c"; alpha: 0.7; colorVariation: 0.1 }
            Emitter {
                id: launcher
                system: fireworks; group: "shell"; enabled: false
                lifeSpan: 4000; size: 5; endSize: 4
                velocity: PointDirection { id: launchVel; y: -600 }
            }
            TrailEmitter {
                system: fireworks; group: "tail"; follow: "shell"
                emitRatePerParticle: 90; lifeSpan: 650; lifeSpanVariation: 250
                maximumEmitted: 1500
                size: 3.5; sizeVariation: 1; endSize: 0.5
                velocity: AngleDirection { angle: 90; angleVariation: 25; magnitude: 30; magnitudeVariation: 20 }
            }
            Gravity { system: fireworks; groups: ["shell"]; magnitude: root.height * 0.5; angle: 90 }

            // one set of stars + their sparkling trails per colour. Written out with
            // fixed group names: Qt's TrailEmitter crashes (or eats memory) when
            // a group name is a binding that changes during creation.
            ImageParticle { groups: ["star0"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ff2a1c"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark0"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#ff2a1c", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark0"; follow: "star0"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit0                                       // red
                readonly property string colour: "#ff2a1c"
                system: fireworks; group: "star0"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            ImageParticle { groups: ["star1"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#fff2e2"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark1"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#fff2e2", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark1"; follow: "star1"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit1                                       // white
                readonly property string colour: "#fff2e2"
                system: fireworks; group: "star1"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            ImageParticle { groups: ["star2"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#3c6cff"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark2"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#3c6cff", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark2"; follow: "star2"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit2                                       // blue
                readonly property string colour: "#3c6cff"
                system: fireworks; group: "star2"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            ImageParticle { groups: ["star3"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ffbf4a"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark3"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#ffbf4a", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark3"; follow: "star3"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit3                                       // gold
                readonly property string colour: "#ffbf4a"
                system: fireworks; group: "star3"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            ImageParticle { groups: ["star4"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#36ff6a"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark4"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#36ff6a", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark4"; follow: "star4"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit4                                       // green
                readonly property string colour: "#36ff6a"
                system: fireworks; group: "star4"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            ImageParticle { groups: ["star5"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#c45cff"; colorVariation: 0.04 }
            ImageParticle { groups: ["spark5"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: Qt.lighter("#c45cff", 1.25); alpha: 0.55; colorVariation: 0.1 }
            TrailEmitter {
                system: fireworks; group: "spark5"; follow: "star5"
                emitRatePerParticle: 26; lifeSpan: 700; lifeSpanVariation: 400
                maximumEmitted: 6000
                size: 2.6; sizeVariation: 1.2; endSize: 0.3
                velocity: AngleDirection { angle: 90; angleVariation: 30; magnitude: 14; magnitudeVariation: 10 }
            }
            Emitter {
                id: kit5                                       // purple
                readonly property string colour: "#c45cff"
                system: fireworks; group: "star5"; enabled: false
                lifeSpan: 1900; lifeSpanVariation: 700
                size: 8.5; sizeVariation: 2; endSize: 2
                velocity: AngleDirection { angleVariation: 180; magnitude: 300; magnitudeVariation: 110 }
            }
            // July 4th: red, white, blue and gold; New Year: everything
            readonly property var kits: root.holiday.name === "july4" || root.previewHoliday === "july4"
                ? [kit0, kit1, kit2, kit3] : [kit0, kit1, kit2, kit3, kit4, kit5]
            readonly property var starGroups: ["star0", "star1", "star2", "star3", "star4", "star5"]
            // willow: heavy gold stars that hang and fall with long trails
            ImageParticle { groups: ["willow"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ffb347" }
            ImageParticle { groups: ["willowSpark"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#ffcf80"; alpha: 0.45 }
            TrailEmitter {
                system: fireworks; group: "willowSpark"; follow: "willow"
                emitRatePerParticle: 40; lifeSpan: 1600; lifeSpanVariation: 600
                maximumEmitted: 9000
                size: 2.4; sizeVariation: 1; endSize: 0.4
                velocity: AngleDirection { angle: 90; angleVariation: 15; magnitude: 10; magnitudeVariation: 8 }
            }
            Emitter {
                id: willowEm
                system: fireworks; group: "willow"; enabled: false
                lifeSpan: 3600; lifeSpanVariation: 800
                size: 5; sizeVariation: 1; endSize: 2
                velocity: AngleDirection { id: willowVel; angleVariation: 180; magnitude: 260; magnitudeVariation: 90 }
            }
            // air drag slows stars fast; then gravity takes them down
            Friction { system: fireworks; groups: ["willow"]; factor: 1.4 }
            Friction { system: fireworks; groups: fireworks.starGroups; factor: 1.9 }
            Gravity { system: fireworks; groups: ["willow"].concat(fireworks.starGroups); magnitude: root.height * 0.07; angle: 90 }

            // smoke left hanging where the shells broke, drifting on the wind
            ImageParticle { groups: ["smoke"]; system: fireworks; source: Qt.resolvedUrl("images/smoke.png"); color: "#33312d"; alpha: 0.035; alphaVariation: 0.015; rotationVariation: 180 }
            // the flash when a shell breaks
            ImageParticle { groups: ["flash"]; system: fireworks; source: "qrc:///particleresources/glowdot.png"; color: "#fff1d6"; entryEffect: ImageParticle.Fade }
            Emitter {
                id: flashEm
                system: fireworks; group: "flash"; enabled: false
                lifeSpan: 260; size: root.height * 0.09; endSize: root.height * 0.03
            }
            Emitter {
                id: smokeEm
                system: fireworks; group: "smoke"; enabled: false
                lifeSpan: 11000; lifeSpanVariation: 3000
                size: root.height * 0.07; sizeVariation: root.height * 0.03; endSize: root.height * 0.22
                velocity: AngleDirection { angleVariation: 180; magnitude: 14; magnitudeVariation: 8 }
                acceleration: PointDirection { x: root.windX * Math.min(root.effWind, 20) * 0.4; y: -1.5 }
            }

            // Where to put a shell: open sky in front of the current photo
            function spot() {
                const H = root.height, W = root.width;
                let sky = [];
                const layer = root.photoMode ? (photoView.aFront ? photoA : photoB) : null;
                if (layer && layer.skyline) {
                    const n = layer.skyline.length;
                    for (let i = 0; i < n; i++) {
                        const p = layer.toScreen((i + 0.5) / n, layer.skyline[i]);
                        if (p.x > 0.06 && p.x < 0.94 && p.y > 0.22) sky.push(p);
                    }
                }
                if (!root.photoMode) for (let i = 1; i < 16; i++) sky.push(Qt.point(i / 16, 0.62));
                if (!sky.length) return null;
                const p = sky[Math.floor(Math.random() * sky.length)];
                const top = 0.06, bottom = Math.max(top + 0.04, Math.min(p.y - 0.1, 0.55));
                return { x: p.x * W, y: (top + Math.random() * (bottom - top)) * H, from: Math.min(1.02, p.y + 0.06) * H };
            }
            function launch() {
                const s = spot();
                if (!s) return;
                const g = root.height * 0.5;
                const rise = s.from - s.y;
                const v = Math.sqrt(2 * g * rise), t = v / g;
                const drift = (Math.random() - 0.5) * 30 + root.windX * Math.min(root.effWind, 20) * 1.5;
                launcher.x = s.x - drift * t; launcher.y = s.from;
                launchVel.x = drift; launchVel.y = -v;
                launcher.lifeSpan = t * 1000;
                launcher.burst(1);
                pending = pending.concat([{ at: Date.now() + t * 1000, x: s.x, y: s.y }]);   // reassign so bindings see it
            }
            function bang(b) {
                const scale = 0.75 + Math.random() * 0.6;
                const R = root.height * 0.16 * scale;        // how far the stars fly
                if (Math.random() < 0.2) {
                    willowEm.x = b.x; willowEm.y = b.y;
                    willowVel.magnitude = R * 1.4; willowVel.magnitudeVariation = R * 0.45;
                    willowEm.burst(Math.round(110 * scale));
                    root.fwColour = Qt.vector3d(1.0, 0.72, 0.35);
                } else {
                    const k = kits[Math.floor(Math.random() * kits.length)];
                    k.x = b.x; k.y = b.y;
                    k.velocity.magnitude = R * 1.9; k.velocity.magnitudeVariation = R * 0.7;
                    k.burst(Math.round(150 * scale));
                    // sometimes a second colour in the same shell
                    if (Math.random() < 0.3) {
                        const k2 = kits[Math.floor(Math.random() * kits.length)];
                        k2.x = b.x; k2.y = b.y;
                        k2.velocity.magnitude = R * 1.1; k2.velocity.magnitudeVariation = R * 0.3;
                        k2.burst(Math.round(60 * scale));
                    }
                    const c = Qt.color(k.colour);
                    root.fwColour = Qt.vector3d(c.r, c.g, c.b);
                }
                smokeEm.x = b.x; smokeEm.y = b.y; smokeEm.burst(4);
                flashEm.x = b.x; flashEm.y = b.y; flashEm.burst(1);
                root.fwLevel = 0.45 * scale * (0.6 + 0.4 * (b.y / root.height));
                fwFade.restart();
            }
        }
        // the show: single shells with pauses, now and then a quick volley
        Timer {
            running: fireworks.running
            repeat: true; interval: 1200
            onTriggered: {
                const volley = Math.random() < 0.18 ? 2 + Math.floor(Math.random() * 3) : 1;
                for (let i = 0; i < volley; i++) fireworks.launch();
                interval = volley > 1 ? 2500 + Math.random() * 2000 : 700 + Math.random() * 2600;
            }
        }
        Timer {
            running: fireworks.running && fireworks.pending.length > 0
            repeat: true; interval: 30
            onTriggered: {
                const now = Date.now();
                const left = [];
                for (const b of fireworks.pending) (b.at <= now ? fireworks.bang(b) : left.push(b));
                fireworks.pending = left;
            }
        }
    }
    ShaderEffectSource {
        id: fwTex
        sourceItem: fwLayer
        hideSource: root.photoMode
        live: fireworks.running || root.fwLevel > 0
        visible: false
    }

    // The village across the street. Animated (ripples, swaying trees,
    // twinkling lights) at ~20 fps, which is plenty and saves a lot of GPU.
    Item {
        anchors.fill: parent
        visible: !root.photoMode
        layer.enabled: visible
        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("shaders/village.frag.qsb")
            property vector2d resolution: Qt.vector2d(root.width, root.height)
            property vector3d sunDir: root.sunDir
            property vector3d sunCol: root.skyColours.sun
            property vector3d zenCol: root.skyColours.zen
            property vector3d horCol: root.skyColours.hor
            property vector3d pal1: root.palColor(0)
            property vector3d pal2: root.palColor(1)
            property vector3d pal3: root.palColor(2)
            property real time: root.slowClock
            property real lightsOn: root.smooth(0.06, -0.04, root.sunDir.y)
            property real snow: root.snowGround
            property real wetness: root.wetness
            property real rain: (root.kind === "rain" || root.kind === "storm") ? Math.max(0.5, root.intensity) : 0
            property real windAmt: root.clamp(root.effWind / 25)
            property real fog: root.fog
            property real flash: flashLevel.value * 0.6
            property real coverage: root.coverage
            property real holiday: root.holidayIds[root.holiday.name] || 0
        }
    }

    // Rain and snow, falling beyond the (covered) patio
    ParticleSystem {
        id: particles
        anchors.fill: parent
        visible: !root.photoMode
        running: visible && (root.kind === "rain" || root.kind === "storm" || root.kind === "snow")

        readonly property color dropTint: Qt.rgba(0.55 + 0.35 * (1 - root.nightness), 0.6 + 0.3 * (1 - root.nightness),
                                                  0.68 + 0.27 * (1 - root.nightness), 1)
        ImageParticle {
            groups: ["rainFar"]
            source: Qt.resolvedUrl("images/rain.svg")
            color: particles.dropTint
            alpha: 0.18
            autoRotation: true
        }
        ImageParticle {
            groups: ["rainNear"]
            source: Qt.resolvedUrl("images/rain.svg")
            color: particles.dropTint
            alpha: 0.32
            autoRotation: true
        }
        ImageParticle {
            groups: ["snow"]
            source: Qt.resolvedUrl("images/snow.svg")
            color: "white"
            alpha: 0.85 - root.nightness * 0.3
            alphaVariation: 0.3
        }

        readonly property real rainVy: root.height * 1.2
        readonly property real rainVx: root.windX * Math.min(root.effWind, 40) * 14
        readonly property real slant: Math.abs(rainVx) * root.height / rainVy
        readonly property real rainRate: (root.kind === "storm" ? 1 : root.intensity) * root.width
        readonly property bool raining: root.kind === "rain" || root.kind === "storm"

        Emitter {
            group: "rainFar"
            enabled: particles.raining
            x: particles.rainVx > 0 ? -particles.slant : 0; y: -40
            width: root.width + particles.slant; height: 1
            emitRate: particles.rainRate * 0.6
            lifeSpan: 1000 * (root.height + 80) / (particles.rainVy * 0.75)
            size: 20; sizeVariation: 6
            velocity: PointDirection {
                x: particles.rainVx * 0.75; xVariation: 15
                y: particles.rainVy * 0.75; yVariation: particles.rainVy * 0.08
            }
        }
        Emitter {
            group: "rainNear"
            enabled: particles.raining
            x: particles.rainVx > 0 ? -particles.slant : 0; y: -60
            width: root.width + particles.slant; height: 1
            emitRate: particles.rainRate * 0.22
            lifeSpan: 1000 * (root.height + 120) / particles.rainVy
            size: 44; sizeVariation: 10
            velocity: PointDirection {
                x: particles.rainVx; xVariation: 25
                y: particles.rainVy; yVariation: particles.rainVy * 0.1
            }
        }

        Emitter {
            group: "snow"
            enabled: root.kind === "snow"
            x: -root.width * 0.2; y: -30
            width: root.width * 1.4; height: 1
            emitRate: root.intensity * root.width * 0.09
            lifeSpan: 1000 * root.height / 60
            size: 8; sizeVariation: 5
            velocity: PointDirection {
                x: root.windX * Math.min(root.effWind, 30) * 4; xVariation: 15
                y: 75; yVariation: 30
            }
        }
        Wander { groups: ["snow"]; xVariance: 50; pace: 30 }
    }

    // Lightning level, shared by the clouds and a soft full-screen flash
    QtObject { id: flashLevel; property real value: 0 }
    SequentialAnimation {
        id: strike
        NumberAnimation { target: flashLevel; property: "value"; to: 1; duration: 60 }
        NumberAnimation { target: flashLevel; property: "value"; to: 0.15; duration: 110 }
        NumberAnimation { target: flashLevel; property: "value"; to: 0.8; duration: 50 }
        NumberAnimation { target: flashLevel; property: "value"; to: 0; duration: 900; easing.type: Easing.OutQuad }
    }
    Timer {
        running: root.kind === "storm"
        repeat: true; interval: 6000
        onTriggered: { interval = 5000 + Math.random() * 15000; strike.restart(); }
    }
    Rectangle {
        anchors.fill: parent
        color: "#dfe6ff"
        opacity: flashLevel.value * (0.22 - root.nightness * 0.1)
    }

    // The patio in front of you
    ShaderEffect {
        anchors.fill: parent
        visible: root.patioStyle !== "off"
        fragmentShader: Qt.resolvedUrl("shaders/patio.frag.qsb")
        property real railing: root.patioStyle === "full" ? 1 : 0
        property vector2d resolution: Qt.vector2d(root.width, root.height)
        property vector3d sunDir: root.sunDir
        property vector3d sunCol: root.skyColours.sun
        property vector3d zenCol: root.skyColours.zen
        property real time: root.clock
        // String lights: auto = lit from dusk, or forced on / off in the settings
        readonly property string power: configuration.LightsPower || "auto"
        property real lightsOn: power === "on" ? 1 : power === "off" ? 0 : root.smooth(0.06, -0.04, root.sunDir.y)
        Behavior on lightsOn { NumberAnimation { duration: 1200; easing.type: Easing.InOutQuad } }
        property real windAmt: root.clamp(root.effWind / 25)
        property real snowGround: root.snowGround
        property real wet: root.wetness
        property vector3d pal1: root.stringColour(0)
        property vector3d pal2: root.stringColour(1)
        property vector3d pal3: root.stringColour(2)
        property real multi: root.lightsColour === "multi" ? 1 : 0
    }

    }

    // ── Rain on the glass ──
    // Drops land on the window and run down it while it rains, and take a
    // while to dry off after it stops.
    property real glassWet: (kind === "rain" || kind === "storm") ? 0.35 + 0.65 * Math.max(intensity, kind === "storm" ? 1 : 0) : 0
    Behavior on glassWet { NumberAnimation { duration: root.glassWet > 0 ? 8000 : 60000 } }
    ShaderEffectSource {
        id: sceneTex
        sourceItem: sceneRoot
        hideSource: glass.visible
        visible: false
    }
    ShaderEffect {
        id: glass
        anchors.fill: parent
        visible: root.glassWet > 0.01
        fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
        property vector2d resolution: Qt.vector2d(root.width, root.height)
        property real time: root.clock
        property real amount: root.glassWet
        property real windX: root.windX
        property variant scene: sceneTex
    }

    // Readout in the top-right corner
    Column {
        visible: root.configuration.ShowInfo && root.loaded
        anchors { top: parent.top; right: parent.right; topMargin: root.height * 0.05; rightMargin: root.height * 0.035 }
        spacing: 2
        opacity: 0.85
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.7; shadowVerticalOffset: 1 }

        readonly property real fs: root.height / 50
        Text {
            anchors.right: parent.right
            text: Math.round(root.temp) + (root.fahrenheit ? "°F" : "°C")
            color: "white"; font.pixelSize: parent.fs * 2.4; font.weight: Font.Light
        }
        Text {
            anchors.right: parent.right
            text: root.describe(root.effCode) + (root.previewCondition !== "auto" ? "  (preview)" : "")
            color: "white"; font.pixelSize: parent.fs
        }
        Text {
            anchors.right: parent.right
            text: root.configuration.PlaceName + " · " + Qt.formatTime(root.updated, "h:mm AP")
            color: "white"; opacity: 0.7; font.pixelSize: parent.fs * 0.75
        }
    }
}
