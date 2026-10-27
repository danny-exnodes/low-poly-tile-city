import 'dart:math' as math;

import 'mesh.dart';

enum Season { spring, summer, autumn, winter }

int rgb(int r, int g, int b) =>
    0xFF000000 |
    (r.clamp(0, 255) << 16) |
    (g.clamp(0, 255) << 8) |
    b.clamp(0, 255);

int mixColor(int a, int b, double t) {
  final ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255;
  final br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
  return rgb(
    (ar + (br - ar) * t).round(),
    (ag + (bg - ag) * t).round(),
    (ab + (bb - ab) * t).round(),
  );
}

int scaleColor(int c, double f) => rgb(
  ((c >> 16) & 255) * f ~/ 1,
  ((c >> 8) & 255) * f ~/ 1,
  (c & 255) * f ~/ 1,
);

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Sun, sky and season state derived from the time-of-day slider.
class Light {
  /// Hours, 0..24.
  final double hour;
  final Season season;
  int version = 0;

  // Direction towards the sun (normalised).
  late double sx, sy, sz;
  late double sunR, sunG, sunB;
  late double skyR, skyG, skyB;
  late double gndR, gndG, gndB;

  /// 0 = full day, 1 = deep night.
  late double night;

  /// Warm, low sun amount (golden hour), 0..1.
  late double golden;
  late double shadowAlpha;
  late int skyTop, skyBottom, haze;

  Light(this.hour, this.season) {
    // Sun travels east to west, peaking at 13:00.
    final dayPhase = (hour - 6.5) / 13.0; // 0 at sunrise, 1 at sunset
    final elev = math.sin(dayPhase * math.pi) * 1.05; // radians-ish
    final az = math.pi * (0.15 + dayPhase * 0.9);
    final e = elev.clamp(-0.4, 1.2);
    // Use a minimum elevation for direction so lighting never flips.
    final de = math.max(e, 0.12);
    sx = math.cos(az) * math.cos(de);
    // North is -z, east is +x; the sun swings through the south (+z).
    sz = math.sin(az) * math.cos(de) * 0.7 + 0.15;
    sy = math.sin(de);
    final l = math.sqrt(sx * sx + sy * sy + sz * sz);
    sx /= l;
    sy /= l;
    sz /= l;

    night = 1 - _smooth(-0.18, 0.12, elev);
    golden = (1 - _smooth(0.05, 0.55, elev)) * (1 - night);
    final day = 1 - night;

    // Sun colour: white at noon, amber at golden hour, nothing at night.
    final sunI = day * (0.75 + 0.25 * _smooth(0.0, 0.6, elev));
    sunR = sunI * (1.0 + 0.10 * golden);
    sunG = sunI * (0.97 - 0.22 * golden);
    sunB = sunI * (0.92 - 0.45 * golden);

    // Ambient sky / ground hemisphere.
    final amb = 0.34 * day + 0.26;
    skyR = amb * (0.92 + 0.12 * golden) * (1 - 0.40 * night);
    skyG = amb * (0.95 - 0.02 * golden) * (1 - 0.22 * night);
    skyB = amb * (1.04 - 0.08 * golden) * (1 + 0.35 * night);
    gndR = skyR * 0.72;
    gndG = skyG * 0.66;
    gndB = skyB * 0.62;

    shadowAlpha = 0.38 * day * _smooth(0.02, 0.25, elev);

    final dayTop = rgb(222, 214, 200), dayBottom = rgb(238, 226, 206);
    final goldTop = rgb(214, 172, 140), goldBottom = rgb(244, 206, 160);
    final nightTop = rgb(18, 22, 40), nightBottom = rgb(42, 44, 66);
    skyTop = mixColor(mixColor(dayTop, goldTop, golden), nightTop, night);
    skyBottom = mixColor(
      mixColor(dayBottom, goldBottom, golden),
      nightBottom,
      night,
    );
    haze = mixColor(skyBottom, skyTop, 0.3);
  }

  String get label {
    final h = hour;
    if (h < 5 || h >= 21.5) return 'night';
    if (h < 6.5) return 'dawn';
    if (h < 8) return 'sunrise';
    if (h < 11) return 'morning';
    if (h < 15) return 'noon';
    if (h < 17) return 'afternoon';
    if (h < 19.2) return 'golden hour';
    if (h < 20.2) return 'sunset';
    return 'dusk';
  }

  /// Brightness used for unshaded things such as particles.
  double get brightness => (skyG + sunG * 0.7).clamp(0.15, 1.2);

  static const _snow = 0xFFF4F6FA;

  /// Foliage colour for a deciduous tree. [tint] (0..1) varies per tree.
  int foliage(double tint) {
    switch (season) {
      case Season.spring:
        if (tint < 0.22) return mixColor(0xFFF2B8C6, 0xFFFAD9E0, tint * 4);
        if (tint < 0.3) return 0xFFF7F1E6;
        return mixColor(0xFF9BCB5E, 0xFF7DB84E, tint);
      case Season.summer:
        return mixColor(0xFF5E9A3E, 0xFF3F7D33, tint);
      case Season.autumn:
        if (tint < 0.35) return mixColor(0xFFE0571F, 0xFFC93A1E, tint * 3);
        if (tint < 0.7) return mixColor(0xFFF09A2A, 0xFFE87A22, tint);
        if (tint < 0.9) return mixColor(0xFFF2C744, 0xFFE8B030, tint);
        return 0xFF8E9A3C;
      case Season.winter:
        return 0;
    }
  }

  int leafParticle(double tint) {
    if (season == Season.winter) return _snow;
    return foliage(tint);
  }

  int grass(double tint) {
    switch (season) {
      case Season.spring:
        return mixColor(0xFF8CC45A, 0xFF7AB64E, tint);
      case Season.summer:
        return mixColor(0xFF6FA845, 0xFF5E9840, tint);
      case Season.autumn:
        return mixColor(0xFF9DA552, 0xFF8C9348, tint);
      case Season.winter:
        return mixColor(0xFFEDF1F6, 0xFFDDE5EE, tint);
    }
  }

  int crop(int base, double tint) {
    switch (season) {
      case Season.spring:
        return mixColor(0xFFA7CF6A, 0xFF8BBE57, tint);
      case Season.summer:
        return mixColor(0xFFE2C25A, 0xFF9CC25B, tint);
      case Season.autumn:
        return mixColor(0xFFB98A55, 0xFFD9B060, tint);
      case Season.winter:
        return 0xFFE9EEF4;
    }
  }

  /// Computes the final lit colour of a triangle.
  int shade(
    int base,
    int mat,
    double nx,
    double ny,
    double nz,
    double tint,
    int key,
  ) {
    switch (mat) {
      case Mat.branch:
        if (season != Season.winter) return 0;
      case Mat.foliage:
        if (season == Season.winter) return 0;
        final j = 0.82 + ((base >> 16) & 255) / 255 * 0.36;
        base = scaleColor(foliage(tint), j);
      case Mat.conifer:
        final j = 0.85 + ((base >> 16) & 255) / 255 * 0.3;
        base = scaleColor(mixColor(0xFF2F6B45, 0xFF3E7E4A, tint), j);
        if (season == Season.winter && ny > 0.25) {
          base = mixColor(base, _snow, 0.75);
        }
      case Mat.grass:
        final j = 0.94 + ((base >> 16) & 255) / 255 * 0.12;
        base = scaleColor(grass(tint), j);
      case Mat.crop:
        base = crop(base, tint);
      case Mat.roof:
        if (season == Season.winter && ny > 0.35) {
          base = mixColor(base, _snow, 0.85);
        }
      case Mat.paved:
        if (season == Season.winter && ny > 0.5) {
          base = mixColor(base, _snow, 0.55);
        }
      case Mat.water:
        if (season == Season.winter) base = 0xFFCFE2EE;
      default:
        break;
    }

    final dot = nx * sx + ny * sy + nz * sz;
    final d = dot > 0 ? dot : 0.0;
    final h = ny * 0.5 + 0.5;
    final lr = gndR + (skyR - gndR) * h + sunR * d;
    final lg = gndG + (skyG - gndG) * h + sunG * d;
    final lb = gndB + (skyB - gndB) * h + sunB * d;
    var r = ((base >> 16) & 255) * lr;
    var g = ((base >> 8) & 255) * lg;
    var b = (base & 255) * lb;

    if (night > 0.02) {
      double glow = 0;
      int gr = 255, gg = 205, gb = 120;
      if (mat == Mat.window) {
        // Roughly 55% of windows are lit, warmth varies.
        final hsh = (key * 2654435761) & 0xFFFF;
        if (hsh < 36000) {
          glow = night * 0.95;
          if (hsh & 7 == 0) {
            gr = 200;
            gg = 225;
            gb = 255;
          } else if (hsh & 3 == 1) {
            gg = 180;
            gb = 95;
          }
        }
      } else if (mat == Mat.lamp || mat == Mat.headlight) {
        glow = night;
        gg = 220;
        gb = 150;
      } else if (mat == Mat.neon) {
        glow = night;
        gr = (base >> 16) & 255;
        gg = (base >> 8) & 255;
        gb = base & 255;
      }
      if (glow > 0) {
        r += (gr - r) * glow;
        g += (gg - g) * glow;
        b += (gb - b) * glow;
      }
    }
    return 0xFF000000 |
        ((r > 255 ? 255 : r.toInt()) << 16) |
        ((g > 255 ? 255 : g.toInt()) << 8) |
        (b > 255 ? 255 : b.toInt());
  }
}
