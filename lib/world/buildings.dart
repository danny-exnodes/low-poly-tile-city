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

enum RoofKind {
  gable('Gable'),
  hip('Hip'),
  mansard('Mansard'),
  flat('Flat');

  final String label;
  const RoofKind(this.label);
}

/// User choices that override what the seed would generate (#8).
class HouseOptions {
  final int? floors, facade, roof;
  final RoofKind? roofKind;
  const HouseOptions({this.floors, this.facade, this.roof, this.roofKind});
  static const none = HouseOptions();
}

/// Styles a user can pick for an ordinary lot, with their floor range.
const editableStyles = <HouseStyle, (int, int)>{
  HouseStyle.cottage: (1, 3),
  HouseStyle.townhouse: (2, 6),
  HouseStyle.shop: (2, 6),
  HouseStyle.apartment: (4, 10),
  HouseStyle.office: (5, 25),
};

/// Roof shapes each editable style supports.
const roofKindsFor = <HouseStyle, List<RoofKind>>{
  HouseStyle.cottage: [RoofKind.gable, RoofKind.hip, RoofKind.flat],
  HouseStyle.townhouse: [
    RoofKind.mansard,
    RoofKind.gable,
    RoofKind.hip,
    RoofKind.flat,
  ],
  HouseStyle.shop: [
    RoofKind.mansard,
    RoofKind.gable,
    RoofKind.hip,
    RoofKind.flat,
  ],
  HouseStyle.apartment: [RoofKind.flat, RoofKind.hip],
};

/// Pitched / mansard / flat roof over a rectangle at height [h].
void _roof(
  MeshBuilder b,
  RoofKind kind,
  double x0,
  double z0,
  double x1,
  double z1,
  double h,
  int roof,
  int wall, {
  double overhang = 0.3,
  double pitch = 2.6,
}) {
  b.mat = Mat.roof;
  switch (kind) {
    case RoofKind.gable:
      b.gable(
        x0,
        z0,
        x1,
        z1,
        h,
        pitch,
        roof,
        gableColor: wall,
        alongX: (x1 - x0) >= (z1 - z0),
        overhang: overhang,
      );
    case RoofKind.hip:
      b.hip(x0, z0, x1, z1, h, pitch * 0.8, roof, overhang: overhang);
    case RoofKind.mansard:
      b.frustum(
        x0,
        z0,
        x1,
        z1,
        h,
        h + 2.4,
        math.min(1.0, (x1 - x0) * 0.2),
        roof,
        top: 0xFF5B5F68,
      );
    case RoofKind.flat:
      b.box(x0, h, z0, x1, h + 0.12, z1, 0xFF8E8A85);
      b.mat = Mat.plain;
      b.box(x0 - 0.1, h, z0 - 0.1, x1 + 0.1, h + 0.55, z0 + 0.15, wall);
      b.box(x0 - 0.1, h, z1 - 0.15, x1 + 0.1, h + 0.55, z1 + 0.1, wall);
  }
  b.mat = Mat.plain;
}

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

/// Walls of a building as one part per floor (bevelled band + that floor's
/// windows + [extras]), so construction can rise floor by floor (#6) and
/// the softened edges read as low-poly rather than cut paper (#5).
void _body(
  MeshBuilder b,
  double x0,
  double z0,
  double x1,
  double z1,
  int floors,
  double fh,
  int color, {
  double y0 = 0,
  double bevel = 0.2,
  int? top,
  int? frame,
  bool skipGroundFront = false,
  double spacing = 2.5,
  double ww = 1.0,
  double wh = 1.45,
  bool band = false,
  bool noWindows = false,
  void Function(int floor)? extras,
}) {
  for (var f = 0; f < floors; f++) {
    final fy = y0 + f * fh;
    b.part();
    b.box(
      x0,
      fy,
      z0,
      x1,
      fy + fh,
      z1,
      color,
      top: top,
      cap: f == floors - 1,
      bevel: bevel,
    );
    if (!noWindows) {
      windows(
        b,
        x0,
        z0,
        x1,
        z1,
        fy,
        1,
        fh,
        ww: ww,
        wh: wh,
        spacing: spacing,
        frame: frame,
        skipGroundFront: skipGroundFront && f == 0,
        band: band,
      );
    }
    extras?.call(f);
    b.endPart();
  }
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
Mesh buildHouse(
  HouseStyle style,
  double w,
  double d,
  int seed, [
  HouseOptions o = HouseOptions.none,
]) {
  final r = math.Random(seed);
  final b = MeshBuilder();
  switch (style) {
    case HouseStyle.cottage:
      _cottage(b, w, d, r, o);
    case HouseStyle.townhouse:
      _townhouse(b, w, d, r, o);
    case HouseStyle.apartment:
      _apartment(b, w, d, r, o);
    case HouseStyle.office:
      _office(b, w, d, r, o);
    case HouseStyle.shop:
      _townhouse(b, w, d, r, o, shop: true);
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

void _cottage(
  MeshBuilder b,
  double w,
  double d,
  math.Random r,
  HouseOptions o,
) {
  final hw = math.min(w, 9.0) / 2 - 0.8, hd = math.min(d, 9.0) / 2 - 1.2;
  // Random rolls always happen so unedited houses stay identical (#8).
  final rolledFloors = 1 + r.nextInt(2);
  final floors = o.floors ?? rolledFloors;
  final h = floors * 2.9;
  final rolledFacade = _pick(r, Pal.facades);
  final rolledRoof = _pick(r, Pal.roofs);
  final facade = o.facade ?? rolledFacade;
  final roof = o.roof ?? rolledRoof;
  final z0 = -hd + 0.6, z1 = hd + 0.2;
  _body(
    b,
    -hw,
    z0,
    hw,
    z1,
    floors,
    2.9,
    facade,
    bevel: 0.2,
    frame: Pal.frame,
    skipGroundFront: true,
    spacing: 2.3,
    extras: (f) {
      if (f != 0) return;
      _door(b, -hw + 1.5, z1, 0);
      b.mat = Mat.window;
      b.wallRect(0, 1, z1, 0.2, hw - 0.6, 0.9, 2.2, Pal.glass, off: 0.06);
      b.mat = Mat.plain;
    },
  );
  final rolledKind = r.nextBool() ? RoofKind.gable : RoofKind.hip;
  final kind = o.roofKind ?? rolledKind;
  _roof(b, kind, -hw, z0, hw, z1, h, roof, facade, overhang: 0.45, pitch: 2.4);
  if (kind != RoofKind.flat) {
    _chimney(b, hw * 0.5, 0, h + 0.4, 2.2, 0xFF9C5A45);
  }
  // Porch.
  if (r.nextBool()) {
    b.box(-hw + 0.6, 0, z1, -hw + 2.4, 0.25, z1 + 1.2, Pal.stone);
  }
}

void _townhouse(
  MeshBuilder b,
  double w,
  double d,
  math.Random r,
  HouseOptions o, {
  bool shop = false,
}) {
  final hw = w / 2 - 0.15, hd = d / 2 - 0.3;
  final rolledFloors = 3 + r.nextInt(3);
  final floors = o.floors ?? rolledFloors;
  const fh = 3.1;
  final h = floors * fh;
  final rolledFacade = _pick(r, Pal.facades);
  final rolledRoof = _pick(r, Pal.roofs);
  final facade = o.facade ?? rolledFacade;
  final roof = o.roof ?? rolledRoof;
  final frame = r.nextInt(3) == 0 ? null : Pal.frame;
  final spacing = 2.2 + r.nextDouble() * 0.5;
  final shopFront = shop || r.nextInt(3) == 0;
  final aw = _pick(r, Pal.awnings);
  _body(
    b,
    -hw,
    -hd,
    hw,
    hd,
    floors,
    fh,
    facade,
    bevel: 0, // attached rows: side bevels would not show
    frame: frame,
    skipGroundFront: true,
    spacing: spacing,
    extras: (f) {
      if (f != 0) return;
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
      if (shopFront) {
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
      } else {
        _door(b, 0, hd, 0);
        b.mat = Mat.window;
        b.wallRect(0, 1, hd, -hw + 0.6, -1.0, 0.9, 2.4, Pal.glass, off: 0.06);
        b.wallRect(0, 1, hd, 1.0, hw - 0.6, 0.9, 2.4, Pal.glass, off: 0.06);
        b.mat = Mat.plain;
      }
    },
  );
  // Cornice.
  b.box(-hw - 0.2, h - 0.3, -hd - 0.2, hw + 0.2, h, hd + 0.2, 0xFFE9E3D6);
  const kinds = [RoofKind.mansard, RoofKind.gable, RoofKind.hip];
  final rolledKind = kinds[r.nextInt(3)];
  final kind = o.roofKind ?? rolledKind;
  b.mat = Mat.roof;
  if (kind == RoofKind.flat) {
    _roof(b, kind, -hw, -hd, hw, hd, h, roof, facade);
  } else if (kind == RoofKind.mansard) {
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
  } else if (kind == RoofKind.gable) {
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
  final c1 = r.nextBool(), c2 = r.nextBool();
  if (kind != RoofKind.flat) {
    if (c1) _chimney(b, -hw * 0.5, -hd * 0.3, h + 0.6, 2.4, 0xFF9C5A45);
    if (c2) _chimney(b, hw * 0.6, -hd * 0.4, h + 0.6, 2.0, 0xFFB7AFA4);
  }
}

void _apartment(
  MeshBuilder b,
  double w,
  double d,
  math.Random r,
  HouseOptions o,
) {
  final hw = w / 2 - 0.5, hd = d / 2 - 0.5;
  final rolledFloors = 5 + r.nextInt(4);
  final floors = o.floors ?? rolledFloors;
  const fh = 3.0;
  final h = floors * fh;
  final rolledFacade = _pick(r, const [
    0xFFEDE6DA,
    0xFFE2D3BE,
    0xFFD8CFC4,
    0xFFF0E1C8,
    0xFFC9BBAA,
    0xFFE6C7A6,
  ]);
  final facade = o.facade ?? rolledFacade;
  final cols = math.max(1, ((2 * hw - 0.6) / 5.2).floor());
  _body(
    b,
    -hw,
    -hd,
    hw,
    hd,
    floors,
    fh,
    facade,
    bevel: 0.25,
    spacing: 2.6,
    frame: 0xFFF5F2EA,
    skipGroundFront: true,
    extras: (f) {
      if (f == 0) {
        _door(b, 0, hd, 0, w: 1.8, color: 0xFF3A3F47);
        return;
      }
      // Balconies on front.
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
    },
  );
  if (o.roofKind == RoofKind.hip) {
    _roof(
      b,
      RoofKind.hip,
      -hw,
      -hd,
      hw,
      hd,
      h,
      o.roof ?? 0xFF5D6470,
      facade,
      pitch: 3.2,
    );
    return;
  }
  // Parapet and roof plant.
  b.mat = Mat.roof;
  b.box(-hw, h, -hd, hw, h + 0.15, hd, o.roof ?? 0xFF8E8A85);
  b.mat = Mat.plain;
  b.box(-hw, h, -hd, hw, h + 0.6, -hd + 0.25, facade);
  b.box(-hw, h, hd - 0.25, hw, h + 0.6, hd, facade);
  b.box(-hw * 0.4, h, -hd * 0.4, hw * 0.1, h + 1.6, hd * 0.2, 0xFFB9B4AD);
  b.cylinder(hw * 0.5, 0, h, h + 2.2, 0.8, 6, 0xFF9AA3AD);
}

void _office(MeshBuilder b, double w, double d, math.Random r, HouseOptions o) {
  var hw = w / 2 - 0.8, hd = d / 2 - 0.8;
  final rolledTiers = 1 + r.nextInt(3);
  // A chosen floor count builds one straight tower of that height.
  final tiers = o.floors == null ? rolledTiers : 1;
  var y = 0.0;
  final glassy = r.nextBool();
  final rolledBody = _pick(r, const [
    0xFFD9D4CB,
    0xFFB8C2CC,
    0xFF9EAAB6,
    0xFFE4DDD0,
    0xFF8C98A6,
    0xFFC7B9A6,
  ]);
  final body = o.facade ?? rolledBody;
  for (var t = 0; t < tiers; t++) {
    final rolled = (t == 0 ? 5 : 2) + r.nextInt(t == 0 ? 6 : 3);
    final floors = o.floors ?? rolled;
    const fh = 3.2;
    final h = floors * fh;
    final thw = hw, thd = hd, ty = y;
    _body(
      b,
      -hw,
      -hd,
      hw,
      hd,
      floors,
      fh,
      glassy ? 0xFF6E879E : body,
      y0: y,
      bevel: 0.3,
      top: 0xFF8E8A85,
      band: !glassy,
      wh: glassy ? 2.2 : 1.6,
      ww: glassy ? 2.2 : 1.0,
      spacing: glassy ? 3.0 : 2.5,
      skipGroundFront: !glassy && t == 0,
      extras: (f) {
        if (!glassy) return;
        // Horizontal spandrel band.
        final fy = ty + f * fh;
        b.box(
          -thw - 0.05,
          fy,
          -thd - 0.05,
          thw + 0.05,
          fy + 0.7,
          thd + 0.05,
          0xFFDCE1E6,
          cap: false,
        );
      },
    );
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
  b.box(-hw, 0, -hd, hw, h, hd, 0xFFEDEAE3, top: 0xFFB9B4AD, bevel: 0.3);
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
  _body(
    b,
    -hw,
    -hd,
    hw,
    hd,
    5,
    fh,
    0xFFF3F1EC,
    top: 0xFFB9B4AD,
    bevel: 0.3,
    band: true,
    wh: 1.4,
    skipGroundFront: true,
    extras: (f) {
      if (f == 0) {
        b.mat = Mat.window;
        b.wallRect(0, 1, hd, -3, 3, 0.2, 2.8, Pal.glassLight, off: 0.06);
        b.mat = Mat.plain;
        b.box(-4, 3.2, hd, 4, 3.5, hd + 3, 0xFFE9E3D6, bottom: true);
      } else if (f == 3) {
        // Red cross sign.
        b.mat = Mat.neon;
        b.wallRect(0, 1, hd, -0.3, 0.3, 11.5, 14.5, 0xFFE0453A, off: 0.08);
        b.wallRect(0, 1, hd, -1.5, 1.5, 12.7, 13.3, 0xFFE0453A, off: 0.09);
        b.mat = Mat.plain;
      }
    },
  );
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
