import 'dart:math' as math;

import '../engine/mesh.dart';
import 'props.dart';

/// Kinds of ordinary buildings that fill lots.
enum HouseStyle {
  cottage('Cottage'),
  townhouse('Townhouse'),
  apartment('Apartment block'),
  office('Office tower'),
  shop('Corner shop'),
  supermarket('Supermarket'),
  hospital('Hospital'),
  church('Church'),
  barn('Barn'),
  circus('Circus tent'),
  kiosk('Kiosk'),
  stands('Grandstand');

  final String label;
  const HouseStyle(this.label);
}

T _pick<T>(math.Random r, List<T> l) => l[r.nextInt(l.length)];

/// Places window decals on the four walls of a box.
void windows(
  MeshBuilder b,
  double x0,
  double z0,
  double x1,
  double z1,
  double yBase,
  int floors,
  double fh, {
  double ww = 1.0,
  double wh = 1.45,
  double spacing = 2.5,
  int? frame,
  bool skipGroundFront = false,
  bool band = false,
}) {
  void side(int nx, int nz, double plane, double u0, double u1) {
    final len = u1 - u0;
    final cols = math.max(1, ((len - 0.6) / spacing).floor());
    final step = len / cols;
    for (var f = 0; f < floors; f++) {
      if (f == 0 && skipGroundFront && nz == 1) continue;
      final y0 = yBase + f * fh + (fh - wh) * 0.55;
      if (band) {
        b.mat = Mat.window;
        b.wallRect(nx, nz, plane, u0 + 0.3, u1 - 0.3, y0, y0 + wh, Pal.glass);
        b.mat = Mat.plain;
        continue;
      }
      for (var c = 0; c < cols; c++) {
        final uc = u0 + step * (c + 0.5);
        if (frame != null) {
          b.mat = Mat.plain;
          b.wallRect(
            nx,
            nz,
            plane,
            uc - ww / 2 - 0.12,
            uc + ww / 2 + 0.12,
            y0 - 0.15,
            y0 + wh + 0.12,
            frame,
            off: 0.03,
          );
        }
        b.mat = Mat.window;
        b.wallRect(
          nx,
          nz,
          plane,
          uc - ww / 2,
          uc + ww / 2,
          y0,
          y0 + wh,
          Pal.glass,
          off: 0.06,
        );
      }
    }
    b.mat = Mat.plain;
  }

  side(0, 1, z1, x0, x1);
  side(0, -1, z0, x0, x1);
  side(1, 0, x1, z0, z1);
  side(-1, 0, x0, z0, z1);
}

void _door(
  MeshBuilder b,
  double x,
  double zFront,
  double y0, {
  double w = 1.1,
  int color = Pal.door,
}) {
  b.wallRect(
    0,
    1,
    zFront,
    x - w / 2,
    x + w / 2,
    y0,
    y0 + 2.1,
    color,
    off: 0.07,
  );
}

void _chimney(MeshBuilder b, double x, double z, double y0, double h, int c) {
  b.box(x - 0.35, y0, z - 0.35, x + 0.35, y0 + h, z + 0.35, c, top: 0xFF3A3A3A);
}

/// Builds an ordinary building filling a [w] x [d] lot. Front faces +z.
Mesh buildHouse(HouseStyle style, double w, double d, int seed) {
  final r = math.Random(seed);
  final b = MeshBuilder();
  switch (style) {
    case HouseStyle.cottage:
      _cottage(b, w, d, r);
    case HouseStyle.townhouse:
      _townhouse(b, w, d, r);
    case HouseStyle.apartment:
      _apartment(b, w, d, r);
    case HouseStyle.office:
      _office(b, w, d, r);
    case HouseStyle.shop:
      _townhouse(b, w, d, r, shop: true);
    case HouseStyle.supermarket:
      _supermarket(b, w, d, r);
    case HouseStyle.hospital:
      _hospital(b, w, d, r);
    case HouseStyle.church:
      _church(b, w, d, r);
    case HouseStyle.barn:
      _barn(b, w, d, r);
    case HouseStyle.circus:
      _circus(b, w, d, r);
    case HouseStyle.kiosk:
      _kiosk(b, w, d, r);
    case HouseStyle.stands:
      _stands(b, w, d, r);
  }
  // Frames and small decals drop out when the house is tiny on screen.
  return b.build(lodPx: 16);
}

void _cottage(MeshBuilder b, double w, double d, math.Random r) {
  final hw = math.min(w, 9.0) / 2 - 0.8, hd = math.min(d, 9.0) / 2 - 1.2;
  final floors = 1 + r.nextInt(2);
  final h = floors * 2.9;
  final facade = _pick(r, Pal.facades);
  final roof = _pick(r, Pal.roofs);
  final z0 = -hd + 0.6, z1 = hd + 0.2;
  b.box(-hw, 0, z0, hw, h, z1, facade);
  windows(
    b,
    -hw,
    z0,
    hw,
    z1,
    0,
    floors,
    2.9,
    frame: Pal.frame,
    skipGroundFront: true,
    spacing: 2.3,
  );
  _door(b, -hw + 1.5, z1, 0);
  b.mat = Mat.window;
  b.wallRect(0, 1, z1, 0.2, hw - 0.6, 0.9, 2.2, Pal.glass, off: 0.06);
  b.mat = Mat.roof;
  if (r.nextBool()) {
    b.gable(
      -hw,
      z0,
      hw,
      z1,
      h,
      2.4,
      roof,
      gableColor: facade,
      alongX: true,
      overhang: 0.45,
    );
  } else {
    b.hip(-hw, z0, hw, z1, h, 2.2, roof, overhang: 0.45);
  }
  b.mat = Mat.plain;
  _chimney(b, hw * 0.5, 0, h + 0.4, 2.2, 0xFF9C5A45);
  // Porch.
  if (r.nextBool()) {
    b.box(-hw + 0.6, 0, z1, -hw + 2.4, 0.25, z1 + 1.2, Pal.stone);
  }
}

void _townhouse(
  MeshBuilder b,
  double w,
  double d,
  math.Random r, {
  bool shop = false,
}) {
  final hw = w / 2 - 0.15, hd = d / 2 - 0.3;
  final floors = 3 + r.nextInt(3);
  const fh = 3.1;
  final h = floors * fh;
  final facade = _pick(r, Pal.facades);
  final roof = _pick(r, Pal.roofs);
  b.box(-hw, 0, -hd, hw, h, hd, facade);
  // Ground floor plinth band.
  b.box(
    -hw - 0.05,
    0,
    -hd - 0.05,
    hw + 0.05,
    0.6,
    hd + 0.05,
    0xFFBDB3A3,
    cap: false,
  );
  windows(
    b,
    -hw,
    -hd,
    hw,
    hd,
    0,
    floors,
    fh,
    frame: r.nextInt(3) == 0 ? null : Pal.frame,
    skipGroundFront: true,
    spacing: 2.2 + r.nextDouble() * 0.5,
  );
  // Ground floor: shop front or door.
  if (shop || r.nextInt(3) == 0) {
    b.mat = Mat.window;
    b.wallRect(
      0,
      1,
      hd,
      -hw + 0.5,
      hw - 1.8,
      0.4,
      2.5,
      Pal.glassLight,
      off: 0.06,
    );
    b.mat = Mat.plain;
    _door(b, hw - 1.1, hd, 0, color: 0xFF3A3F47);
    final aw = _pick(r, Pal.awnings);
    b.part();
    b.quad(
      V3(-hw + 0.3, 2.9, hd),
      V3(hw - 0.3, 2.9, hd),
      V3(hw - 0.3, 2.5, hd + 1.3),
      V3(-hw + 0.3, 2.5, hd + 1.3),
      aw,
      out: const V3(0, 1, 0.3),
    );
    b.quad(
      V3(-hw + 0.3, 2.5, hd + 1.3),
      V3(hw - 0.3, 2.5, hd + 1.3),
      V3(hw - 0.3, 2.2, hd + 1.3),
      V3(-hw + 0.3, 2.2, hd + 1.3),
      aw,
      out: const V3(0, 0, 1),
    );
    b.endPart();
  } else {
    _door(b, 0, hd, 0);
    b.mat = Mat.window;
    b.wallRect(0, 1, hd, -hw + 0.6, -1.0, 0.9, 2.4, Pal.glass, off: 0.06);
    b.wallRect(0, 1, hd, 1.0, hw - 0.6, 0.9, 2.4, Pal.glass, off: 0.06);
    b.mat = Mat.plain;
  }
  // Cornice.
  b.box(-hw - 0.2, h - 0.3, -hd - 0.2, hw + 0.2, h, hd + 0.2, 0xFFE9E3D6);
  b.mat = Mat.roof;
  final kind = r.nextInt(3);
  if (kind == 0) {
    // Mansard with dormers.
    b.frustum(-hw, -hd, hw, hd, h, h + 2.4, 1.0, roof, top: 0xFF5B5F68);
    b.mat = Mat.plain;
    final n = math.max(1, (w / 3).floor());
    for (var i = 0; i < n; i++) {
      final x = -hw + (i + 0.5) * (2 * hw / n);
      b.box(
        x - 0.45,
        h + 0.6,
        hd - 0.75,
        x + 0.45,
        h + 1.9,
        hd - 0.35,
        0xFFE9E3D6,
      );
      b.mat = Mat.window;
      b.wallRect(
        0,
        1,
        hd - 0.35,
        x - 0.3,
        x + 0.3,
        h + 0.8,
        h + 1.7,
        Pal.glass,
      );
      b.mat = Mat.roof;
      b.gable(
        x - 0.45,
        hd - 0.75,
        x + 0.45,
        hd - 0.35,
        h + 1.9,
        0.5,
        roof,
        alongX: false,
        overhang: 0.08,
      );
    }
  } else if (kind == 1) {
    b.gable(
      -hw,
      -hd,
      hw,
      hd,
      h,
      2.8,
      roof,
      gableColor: facade,
      alongX: true,
      overhang: 0.2,
    );
  } else {
    b.hip(-hw, -hd, hw, hd, h, 2.2, roof, overhang: 0.2);
  }
  b.mat = Mat.plain;
  if (r.nextBool()) _chimney(b, -hw * 0.5, -hd * 0.3, h + 0.6, 2.4, 0xFF9C5A45);
  if (r.nextBool()) _chimney(b, hw * 0.6, -hd * 0.4, h + 0.6, 2.0, 0xFFB7AFA4);
}

void _apartment(MeshBuilder b, double w, double d, math.Random r) {
  final hw = w / 2 - 0.5, hd = d / 2 - 0.5;
  final floors = 5 + r.nextInt(4);
  const fh = 3.0;
  final h = floors * fh;
  final facade = _pick(r, const [
    0xFFEDE6DA,
    0xFFE2D3BE,
    0xFFD8CFC4,
    0xFFF0E1C8,
    0xFFC9BBAA,
    0xFFE6C7A6,
  ]);
  b.box(-hw, 0, -hd, hw, h, hd, facade);
  windows(
    b,
    -hw,
    -hd,
    hw,
    hd,
    0,
    floors,
    fh,
    spacing: 2.6,
    frame: 0xFFF5F2EA,
    skipGroundFront: true,
  );
  _door(b, 0, hd, 0, w: 1.8, color: 0xFF3A3F47);
  // Balconies on front.
  final cols = math.max(1, ((2 * hw - 0.6) / 5.2).floor());
  for (var f = 1; f < floors; f++) {
    for (var c = 0; c < cols; c++) {
      final x = -hw + (c + 0.5) * (2 * hw / cols);
      b.box(
        x - 1.2,
        f * fh,
        hd,
        x + 1.2,
        f * fh + 1.0,
        hd + 0.9,
        0xFFF4F1EA,
        bottom: true,
      );
    }
  }
  // Parapet and roof plant.
  b.mat = Mat.roof;
  b.box(-hw, h, -hd, hw, h + 0.15, hd, 0xFF8E8A85);
  b.mat = Mat.plain;
  b.box(-hw, h, -hd, hw, h + 0.6, -hd + 0.25, facade);
  b.box(-hw, h, hd - 0.25, hw, h + 0.6, hd, facade);
  b.box(-hw * 0.4, h, -hd * 0.4, hw * 0.1, h + 1.6, hd * 0.2, 0xFFB9B4AD);
  b.cylinder(hw * 0.5, 0, h, h + 2.2, 0.8, 6, 0xFF9AA3AD);
}

void _office(MeshBuilder b, double w, double d, math.Random r) {
  var hw = w / 2 - 0.8, hd = d / 2 - 0.8;
  final tiers = 1 + r.nextInt(3);
  var y = 0.0;
  final glassy = r.nextBool();
  final body = _pick(r, const [
    0xFFD9D4CB,
    0xFFB8C2CC,
    0xFF9EAAB6,
    0xFFE4DDD0,
    0xFF8C98A6,
    0xFFC7B9A6,
  ]);
  for (var t = 0; t < tiers; t++) {
    final floors = (t == 0 ? 5 : 2) + r.nextInt(t == 0 ? 6 : 3);
    const fh = 3.2;
    final h = floors * fh;
    b.box(
      -hw,
      y,
      -hd,
      hw,
      y + h,
      hd,
      glassy ? 0xFF6E879E : body,
      top: 0xFF8E8A85,
    );
    if (glassy) {
      // Horizontal spandrel bands.
      for (var f = 0; f < floors; f++) {
        final fy = y + f * fh;
        b.box(
          -hw - 0.05,
          fy,
          -hd - 0.05,
          hw + 0.05,
          fy + 0.7,
          hd + 0.05,
          0xFFDCE1E6,
          cap: false,
        );
      }
      b.mat = Mat.window;
      windows(
        b,
        -hw,
        -hd,
        hw,
        hd,
        y,
        floors,
        fh,
        wh: 2.2,
        spacing: 3.0,
        ww: 2.2,
      );
    } else {
      windows(
        b,
        -hw,
        -hd,
        hw,
        hd,
        y,
        floors,
        fh,
        band: true,
        wh: 1.6,
        skipGroundFront: t == 0,
      );
    }
    y += h;
    if (t < tiers - 1) {
      hw *= 0.78;
      hd *= 0.78;
    }
  }
  if (!glassy) {
    b.mat = Mat.window;
    b.wallRect(
      0,
      1,
      d / 2 - 0.8,
      -w / 2 + 1.6,
      w / 2 - 1.6,
      0.2,
      2.8,
      Pal.glassLight,
      off: 0.06,
    );
    b.mat = Mat.plain;
  }
  // Roof equipment.
  b.box(-hw * 0.5, y, -hd * 0.5, hw * 0.3, y + 2.0, hd * 0.4, 0xFFB0ABA3);
  if (r.nextInt(3) == 0) {
    b.cylinder(0, 0, y, y + 8, 0.12, 4, Pal.darkMetal);
    b.mat = Mat.lamp;
    b.box(-0.2, y + 8, -0.2, 0.2, y + 8.4, 0.2, 0xFFD94436);
    b.mat = Mat.plain;
  } else {
    b.mat = Mat.neon;
    b.box(-hw * 0.3, y, hd * 0.6, hw * 0.3, y + 0.25, hd * 0.9, 0xFFB7E0FF);
    b.mat = Mat.plain;
  }
}

void _supermarket(MeshBuilder b, double w, double d, math.Random r) {
  final hw = w / 2 - 0.5, hd = d / 2 - 0.5;
  const h = 6.0;
  b.box(-hw, 0, -hd, hw, h, hd, 0xFFEDEAE3, top: 0xFFB9B4AD);
  b.box(
    -hw - 0.1,
    h - 1.6,
    -hd - 0.1,
    hw + 0.1,
    h,
    hd + 0.1,
    0xFF2F8F4E,
    cap: false,
  );
  b.mat = Mat.window;
  b.wallRect(0, 1, hd, -hw + 1, hw - 1, 0.2, 3.4, Pal.glassLight, off: 0.06);
  b.mat = Mat.neon;
  b.box(-hw * 0.5, h, hd - 0.4, hw * 0.5, h + 1.4, hd - 0.1, 0xFF42C46A);
  b.mat = Mat.plain;
  b.wallRect(
    0,
    1,
    hd - 0.1,
    -hw * 0.45,
    hw * 0.45,
    h + 0.35,
    h + 1.05,
    0xFFF7F7F2,
    off: 0.05,
  );
  // Canopy.
  b.box(-hw * 0.4, 3.6, hd, hw * 0.4, 3.9, hd + 2.2, 0xFF2F8F4E, bottom: true);
  // Roof units.
  for (var i = 0; i < 3; i++) {
    b.box(
      -hw + 3 + i * 5.0,
      h,
      -hd + 2,
      -hw + 5 + i * 5.0,
      h + 1.2,
      -hd + 4,
      0xFFB0ABA3,
    );
  }
}

void _hospital(MeshBuilder b, double w, double d, math.Random r) {
  final hw = w / 2 - 0.5, hd = d / 2 - 0.5;
  const fh = 3.2;
  b.box(-hw, 0, -hd, hw, 5 * fh, hd, 0xFFF3F1EC, top: 0xFFB9B4AD);
  windows(
    b,
    -hw,
    -hd,
    hw,
    hd,
    0,
    5,
    fh,
    band: true,
    wh: 1.4,
    skipGroundFront: true,
  );
  b.mat = Mat.window;
  b.wallRect(0, 1, hd, -3, 3, 0.2, 2.8, Pal.glassLight, off: 0.06);
  b.mat = Mat.plain;
  b.box(-4, 3.2, hd, 4, 3.5, hd + 3, 0xFFE9E3D6, bottom: true);
  // Red cross sign.
  b.mat = Mat.neon;
  b.wallRect(0, 1, hd, -0.3, 0.3, 11.5, 14.5, 0xFFE0453A, off: 0.08);
  b.wallRect(0, 1, hd, -1.5, 1.5, 12.7, 13.3, 0xFFE0453A, off: 0.09);
  b.mat = Mat.plain;
}

void _church(MeshBuilder b, double w, double d, math.Random r) {
  final hw = math.min(w / 2 - 1.5, 6.0), hd = d / 2 - 1;
  const stone = 0xFFD8CDB8;
  const roof = 0xFF5D6470;
  b.box(-hw, 0, -hd, hw, 9, hd - 5, stone);
  for (var i = 0; i < 4; i++) {
    final z = -hd + 2 + i * (2 * hd - 8) / 4;
    b.mat = Mat.window;
    b.wallRect(1, 0, hw, z, z + 1.2, 3, 7, 0xFF5C6E9C);
    b.wallRect(-1, 0, -hw, z, z + 1.2, 3, 7, 0xFF5C6E9C);
    b.mat = Mat.plain;
  }
  b.mat = Mat.roof;
  b.gable(
    -hw,
    -hd,
    hw,
    hd - 5,
    9,
    5,
    roof,
    gableColor: stone,
    alongX: false,
    overhang: 0.3,
  );
  b.mat = Mat.plain;
  // Tower.
  b.box(-2.5, 0, hd - 5, 2.5, 17, hd, stone);
  b.mat = Mat.window;
  b.wallRect(0, 1, hd, -0.8, 0.8, 12, 15, 0xFF5C6E9C);
  b.mat = Mat.plain;
  _door(b, 0, hd, 0, w: 1.8);
  b.lathe(
    0,
    hd - 2.5,
    [17, 27],
    [3.2, 0],
    4,
    roof,
    rot: math.pi / 4,
    capTop: false,
  );
  b.beam(V3(0, 27, hd - 2.5), V3(0, 29.5, hd - 2.5), 0.15, 0xFFD4AF37);
  b.beam(V3(-0.6, 28.8, hd - 2.5), V3(0.6, 28.8, hd - 2.5), 0.15, 0xFFD4AF37);
}

void _barn(MeshBuilder b, double w, double d, math.Random r) {
  final hw = math.min(w / 2 - 1, 5.0), hd = math.min(d / 2 - 1, 7.0);
  b.box(-hw, 0, -hd, hw, 5, hd, 0xFFA8382E);
  b.wallRect(0, 1, hd, -1.8, 1.8, 0, 3.8, 0xFFF2EDE4, off: 0.05);
  b.wallRect(0, 1, hd, -1.5, 1.5, 0.2, 3.5, 0xFF7A2A22, off: 0.07);
  b.mat = Mat.roof;
  b.gable(
    -hw,
    -hd,
    hw,
    hd,
    5,
    3.5,
    0xFF5B5F68,
    gableColor: 0xFFA8382E,
    alongX: false,
    overhang: 0.4,
  );
  b.mat = Mat.plain;
  // Silo.
  b.cylinder(hw + 2, -hd + 2, 0, 9, 1.6, 8, 0xFFC9CED4, capTop: false);
  b.mat = Mat.roof;
  b.sphere(hw + 2, 9, -hd + 2, 1.6, 8, 4, 0xFF8A9099, squash: 0.6);
  b.mat = Mat.plain;
}

void _circus(MeshBuilder b, double w, double d, math.Random r) {
  final rad = math.min(w, d) / 2 - 1.0;
  const red = 0xFFD8402F, white = 0xFFF5EFE4;
  // Striped walls and roof via alternating segments.
  b.part();
  for (var i = 0; i < 16; i++) {
    final a0 = i * 2 * math.pi / 16, a1 = (i + 1) * 2 * math.pi / 16;
    final c = i.isEven ? red : white;
    final p0 = V3(math.cos(a0) * rad, 0, math.sin(a0) * rad);
    final p1 = V3(math.cos(a1) * rad, 0, math.sin(a1) * rad);
    final top = V3(0, 11, 0);
    final q0 = V3(math.cos(a0) * rad, 4.5, math.sin(a0) * rad);
    final q1 = V3(math.cos(a1) * rad, 4.5, math.sin(a1) * rad);
    final out = V3(math.cos((a0 + a1) / 2), 0, math.sin((a0 + a1) / 2));
    b.quad(p0, p1, q1, q0, c, out: out);
    b.tri(q0, q1, top, c, out: out + const V3(0, 0.8, 0));
  }
  b.endPart();
  b.cylinder(0, 0, 11, 13, 0.1, 4, Pal.darkMetal);
  b.mat = Mat.neon;
  b.box(0, 12.2, -0.05, 1.4, 13, 0.05, 0xFFF2C744, bottom: true);
  b.mat = Mat.plain;
  b.wallRect(0, 1, rad, -1.2, 1.2, 0, 3, 0xFF5A2A20, off: 0.1);
}

void _kiosk(MeshBuilder b, double w, double d, math.Random r) {
  final c = _pick(r, Pal.awnings);
  b.box(-1.5, 0, -1.2, 1.5, 2.6, 1.2, 0xFFF2EDE4);
  b.mat = Mat.window;
  b.wallRect(0, 1, 1.2, -1.2, 1.2, 1.0, 2.2, Pal.glassLight);
  b.mat = Mat.roof;
  b.hip(-1.5, -1.2, 1.5, 1.2, 2.6, 1.0, c, overhang: 0.4);
  b.mat = Mat.plain;
}

void _stands(MeshBuilder b, double w, double d, math.Random r) {
  final hw = w / 2 - 0.5;
  for (var i = 0; i < 4; i++) {
    b.box(
      -hw,
      0,
      -1.5 + i * 0.0,
      hw,
      0.8 + i * 0.8,
      1.6 - i * 0.8,
      i.isEven ? 0xFF3A6EA5 : 0xFFD8D4CB,
    );
  }
  b.box(-hw, 3.6, -1.6, hw, 3.8, 1.8, 0xFFEDEAE3, bottom: true);
  b.box(-hw, 0, -1.6, -hw + 0.2, 3.6, -1.4, Pal.darkMetal);
  b.box(hw - 0.2, 0, -1.6, hw, 3.6, -1.4, Pal.darkMetal);
}
