import 'dart:math' as math;

import '../engine/mesh.dart';
import 'props.dart';

enum Monument {
  tokyoTower('Tokyo Tower'),
  christRedeemer('Christ the Redeemer'),
  petronas('Petronas Towers'),
  sagrada('Sagrada Familia'),
  stBasil("St Basil's Cathedral"),
  atomium('Atomium'),
  gatewayArch('Gateway Arch'),
  stonehenge('Stonehenge'),
  windmill('Dutch windmill'),
  moai('Moai of Easter Island');

  final String label;
  const Monument(this.label);
}

/// Geometry for a monument at a nominal 14 m footprint. [spinner] is an
/// optional part rotating around its local Z axis, placed at [spinnerAt].
class MonumentModel {
  final Mesh main;
  final Mesh? spinner;
  final V3 spinnerAt;
  final double spinRate;
  MonumentModel(
    this.main, {
    this.spinner,
    this.spinnerAt = const V3(0, 0, 0),
    this.spinRate = 0,
  });
}

MonumentModel buildMonument(Monument m) {
  final b = MeshBuilder(sortParts: true);
  switch (m) {
    case Monument.tokyoTower:
      _tokyo(b);
    case Monument.christRedeemer:
      _christ(b);
    case Monument.petronas:
      _petronas(b);
    case Monument.sagrada:
      _sagrada(b);
    case Monument.stBasil:
      _stBasil(b);
    case Monument.atomium:
      _atomium(b);
    case Monument.gatewayArch:
      _arch(b);
    case Monument.stonehenge:
      _stonehenge(b);
    case Monument.windmill:
      _windmillBody(b);
      return MonumentModel(
        b.build(),
        spinner: buildWindmillSails(),
        spinnerAt: const V3(0, 13.4, 2.6),
        spinRate: 1,
      );
    case Monument.moai:
      _moai(b);
  }
  return MonumentModel(b.build());
}

const _orange = 0xFFE8562A;
const _white = 0xFFF2EEE6;

void _tokyo(MeshBuilder b) {
  // Four splayed legs.
  for (final (sx, sz) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
    b.beam(V3(sx * 6.0, 0, sz * 6.0), V3(sx * 2.4, 13, sz * 2.4), 1.0, _orange);
    b.beam(V3(sx * 4.8, 4.5, sz * 4.8), V3(sx * 3.5, 9, sz * 3.5), 0.4, _white);
  }
  // Lattice cross beams.
  for (final y in const [4.5, 9.0]) {
    final e = 6.0 - y * 0.28;
    b.beam(V3(-e, y, -e), V3(e, y, -e), 0.3, _orange);
    b.beam(V3(-e, y, e), V3(e, y, e), 0.3, _orange);
    b.beam(V3(-e, y, -e), V3(-e, y, e), 0.3, _orange);
    b.beam(V3(e, y, -e), V3(e, y, e), 0.3, _orange);
  }
  // Main deck.
  b.box(-3.2, 13, -3.2, 3.2, 16, 3.2, _white, top: 0xFF9AA3AD);
  b.mat = Mat.window;
  b.wallRect(0, 1, 3.2, -2.8, 2.8, 13.8, 15.4, Pal.glass);
  b.wallRect(1, 0, 3.2, -2.8, 2.8, 13.8, 15.4, Pal.glass);
  b.wallRect(0, -1, -3.2, -2.8, 2.8, 13.8, 15.4, Pal.glass);
  b.wallRect(-1, 0, -3.2, -2.8, 2.8, 13.8, 15.4, Pal.glass);
  b.mat = Mat.plain;
  // Upper shaft in alternating bands.
  var y = 16.0, half = 2.2;
  for (var i = 0; i < 4; i++) {
    final ny = y + 3.4, nh = half - 0.28;
    b.frustum(
      -half,
      -half,
      half,
      half,
      y,
      ny,
      half - nh,
      i.isEven ? _orange : _white,
      cap: false,
    );
    y = ny;
    half = nh;
  }
  b.box(-1.7, y, -1.7, 1.7, y + 1.6, 1.7, _white, top: 0xFF9AA3AD);
  b.mat = Mat.window;
  b.wallRect(0, 1, 1.7, -1.4, 1.4, y + 0.3, y + 1.3, Pal.glass);
  b.wallRect(1, 0, 1.7, -1.4, 1.4, y + 0.3, y + 1.3, Pal.glass);
  b.wallRect(0, -1, -1.7, -1.4, 1.4, y + 0.3, y + 1.3, Pal.glass);
  b.wallRect(-1, 0, -1.7, -1.4, 1.4, y + 0.3, y + 1.3, Pal.glass);
  b.mat = Mat.plain;
  y += 1.6;
  for (var i = 0; i < 3; i++) {
    b.frustum(
      -0.7 + i * 0.18,
      -0.7 + i * 0.18,
      0.7 - i * 0.18,
      0.7 - i * 0.18,
      y,
      y + 3,
      0.18,
      i.isEven ? _orange : _white,
      cap: i == 2,
    );
    y += 3;
  }
  b.cylinder(0, 0, y, y + 6, 0.12, 4, _white);
  b.mat = Mat.lamp;
  b.box(-0.2, y + 6, -0.2, 0.2, y + 6.4, 0.2, 0xFFD94436);
  b.mat = Mat.plain;
}

void _christ(MeshBuilder b) {
  b.mat = Mat.grass;
  b.lathe(
    0,
    0,
    [0, 1.8, 3.6, 5.0],
    [7.5, 6.2, 3.8, 2.2],
    12,
    rgb8(140),
    capTop: true,
  );
  b.mat = Mat.plain;
  const stone = 0xFFE6E1D3;
  b.box(-1.5, 5, -1.5, 1.5, 8.5, 1.5, 0xFFCFC8B8);
  b.frustum(-1.2, -0.8, 1.2, 0.8, 8.5, 16.5, 0.35, stone, insetZ: 0.15);
  b.box(-5.6, 15.4, -0.4, 5.6, 16.3, 0.4, stone, bottom: true);
  b.box(-0.45, 16.5, -0.45, 0.45, 17.6, 0.45, stone);
}

void _petronas(MeshBuilder b) {
  const silver = 0xFFCAD1D9, band = 0xFF7F8EA0;
  for (final x in const [-4.6, 4.6]) {
    final ys = <double>[], rs = <double>[];
    final steps = [
      (0.0, 2.7),
      (24.0, 2.7),
      (24.0, 2.3),
      (31.0, 2.3),
      (31.0, 1.9),
      (36.0, 1.9),
      (36.0, 1.5),
      (40.0, 1.5),
      (40.0, 1.1),
      (43.0, 1.1),
      (46.0, 0.5),
      (47.0, 0.0),
    ];
    // Insert banded rings between big steps.
    for (var i = 0; i < steps.length; i++) {
      final (y, r) = steps[i];
      ys.add(y);
      rs.add(r);
      if (i + 1 < steps.length &&
          steps[i + 1].$1 - y > 3 &&
          steps[i + 1].$2 == r) {
        for (var yy = y + 2.4; yy < steps[i + 1].$1 - 0.5; yy += 2.4) {
          ys.add(yy);
          rs.add(r);
        }
      }
    }
    b.lathe(
      x,
      0,
      ys,
      rs,
      12,
      silver,
      colors: const [silver, band],
      capTop: false,
      rot: math.pi / 8,
    );
    b.cylinder(x, 0, 47, 56, 0.15, 4, silver);
  }
  // Sky bridge.
  b.box(-2.5, 17, -0.7, 2.5, 18.6, 0.7, 0xFF9AA3AD, bottom: true);
  b.beam(const V3(-2.3, 10, 0), const V3(-0.2, 17, 0), 0.3, silver);
  b.beam(const V3(2.3, 10, 0), const V3(0.2, 17, 0), 0.3, silver);
}

void _sagrada(MeshBuilder b) {
  const tan = 0xFFC9B48C, dark = 0xFFA89470;
  b.box(-6, 0, -4, 6, 12, 4, tan);
  b.mat = Mat.window;
  b.wallRect(0, 1, 4, -1.2, 1.2, 2, 9, 0xFF8A6D9C);
  b.mat = Mat.roof;
  b.gable(-6, -4, 6, 4, 12, 5, dark, gableColor: tan, alongX: true);
  b.mat = Mat.plain;
  void spire(double x, double z, double h, int finial) {
    b.lathe(
      x,
      z,
      [0, h * 0.55, h * 0.9, h],
      [1.15, 0.95, 0.35, 0],
      6,
      tan,
      colors: const [tan, dark, tan],
      capTop: false,
    );
    b.sphere(x, h + 0.4, z, 0.55, 5, 3, finial);
  }

  const fin = [0xFFD8402F, 0xFFF2C744, 0xFF3F8F5A, 0xFFF5EFE4];
  final xs = [-4.5, -1.5, 1.5, 4.5];
  for (var i = 0; i < 4; i++) {
    spire(xs[i], 5.2, i == 1 || i == 2 ? 30 : 25, fin[i]);
    spire(xs[i], -5.2, i == 1 || i == 2 ? 27 : 22, fin[(i + 2) % 4]);
  }
  spire(0, 0, 40, 0xFFF2C744);
}

void _stBasil(MeshBuilder b) {
  const brick = 0xFFB5523B, white = 0xFFF2ECE0;
  b.box(-6.5, 0, -6.5, 6.5, 3, 6.5, brick, top: white);
  b.lathe(
    0,
    0,
    [3, 12, 12.6, 14, 22, 30],
    [2.4, 2.4, 2.8, 2.0, 1.4, 0],
    8,
    brick,
    colors: const [brick, white, white, 0xFFE8DCC0, 0xFF3F8F5A],
    capTop: false,
  );
  _onion(b, 0, 30, 0, 0.8, const [0xFFE3B341]);
  const domes = [
    [0xFF3F8F5A, 0xFFF2C744],
    [0xFF2F5D8C, 0xFFF2ECE0],
    [0xFFD8402F, 0xFF3F8F5A],
    [0xFFF2C744, 0xFFD8402F],
  ];
  var i = 0;
  for (final (x, z, h) in const [
    (-4.3, -4.3, 9.0),
    (4.3, -4.3, 9.5),
    (4.3, 4.3, 9.0),
    (-4.3, 4.3, 9.5),
  ]) {
    b.lathe(
      x,
      z,
      [3, h, h + 0.4],
      [1.3, 1.3, 1.5],
      10,
      brick,
      colors: const [brick, white],
      capTop: true,
    );
    _onion(b, x, h + 0.4, z, 1.4, domes[i % 4]);
    i++;
  }
  for (final (x, z) in const [
    (0.0, -5.6),
    (5.6, 0.0),
    (0.0, 5.6),
    (-5.6, 0.0),
  ]) {
    b.lathe(x, z, [3, 7, 7.3], [1.0, 1.0, 1.15], 10, white, capTop: true);
    _onion(b, x, 7.3, z, 1.0, domes[(i + 1) % 4]);
    i++;
  }
}

void _onion(
  MeshBuilder b,
  double x,
  double y,
  double z,
  double s,
  List<int> c,
) {
  b.lathe(
    x,
    z,
    [y, y + 0.5 * s, y + 1.2 * s, y + 1.9 * s, y + 2.5 * s, y + 3.2 * s],
    [0.8 * s, 1.15 * s, 1.2 * s, 0.85 * s, 0.35 * s, 0],
    10,
    c[0],
    segColors: c,
    capTop: false,
  );
  b.cylinder(x, z, y + 3.2 * s, y + 4 * s, 0.07, 3, 0xFFE3B341);
}

void _atomium(MeshBuilder b) {
  const steel = 0xFFD0D6DE, tube = 0xFFB4BCC6;
  const a = 5.2;
  final ey = const V3(1, 1, 1).normalized;
  final ex = const V3(1, -1, 0).normalized;
  final ez = ex.cross(ey);
  V3 map(V3 v) => V3(v.dot(ex), v.dot(ey) + a * math.sqrt(3) + 3.5, v.dot(ez));
  final corners = <V3>[];
  for (final sx in const [-1, 1]) {
    for (final sy in const [-1, 1]) {
      for (final sz in const [-1, 1]) {
        corners.add(map(V3(sx * a, sy * a, sz * a)));
      }
    }
  }
  final center = map(const V3(0, 0, 0));
  final low = corners.reduce((p, q) => p.y < q.y ? p : q);
  // Supports.
  b.tube(V3(low.x, 0, low.z), low, 0.5, 6, tube);
  for (var k = 0; k < 3; k++) {
    final ang = k * 2 * math.pi / 3;
    b.beam(
      V3(math.cos(ang) * 4.5, 0, math.sin(ang) * 4.5),
      low + V3(math.cos(ang) * 0.8, 1.2, math.sin(ang) * 0.8),
      0.35,
      tube,
    );
  }
  // Edges and diagonals.
  for (var i = 0; i < 8; i++) {
    for (var j = i + 1; j < 8; j++) {
      if ((i ^ j).bitCount == 1) b.tube(corners[i], corners[j], 0.42, 6, tube);
    }
    b.tube(corners[i], center, 0.42, 6, tube);
  }
  for (final c in [...corners, center]) {
    b.sphere(c.x, c.y, c.z, 1.9, 10, 6, steel);
  }
}

extension on int {
  int get bitCount {
    var v = this, c = 0;
    while (v != 0) {
      c += v & 1;
      v >>= 1;
    }
    return c;
  }
}

void _arch(MeshBuilder b) {
  const steel = 0xFFD3D7DC;
  const halfSpan = 9.5, height = 30.0;
  // Solve a*(cosh(L/a)-1) = H for a.
  double cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  var lo = 0.5, hi = 50.0;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (mid * (cosh(halfSpan / mid) - 1) > height) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = (lo + hi) / 2;
  const n = 22;
  V3 pt(double t) {
    final x = -halfSpan + 2 * halfSpan * t;
    return V3(x, height - a * (cosh(x / a) - 1), 0);
  }

  // Sample by arc so segments are even.
  for (var i = 0; i < n; i++) {
    final t0 = 0.5 - 0.5 * math.cos(math.pi * i / n);
    final t1 = 0.5 - 0.5 * math.cos(math.pi * (i + 1) / n);
    final mid = (t0 + t1) / 2;
    final w = 1.0 + 0.9 * (2 * (mid - 0.5)).abs();
    b.beam(pt(t0), pt(t1), w, steel);
  }
  b.mat = Mat.paved;
  b.box(-11, 0, -2.5, 11, 0.25, 2.5, Pal.paving);
  b.mat = Mat.plain;
}

void _stonehenge(MeshBuilder b) {
  b.mat = Mat.grass;
  b.lathe(0, 0, [0, 0.15], [7.6, 7.4], 12, rgb8(160), capTop: true);
  b.mat = Mat.plain;
  final r = math.Random(7);
  int stone() => [0xFFA39E93, 0xFF9A958A, 0xFFB0AA9E][r.nextInt(3)];
  const n = 14;
  final tops = <V3>[];
  for (var i = 0; i < n; i++) {
    final ang = i * 2 * math.pi / n;
    final c = V3(math.cos(ang) * 6.2, 0, math.sin(ang) * 6.2);
    if (i == 9) {
      // Fallen stone.
      b.obox(
        c + const V3(0, 0.4, 0),
        V3(math.cos(ang) * 1.4, 0, math.sin(ang) * 1.4),
        const V3(0, 0.4, 0),
        V3(-math.sin(ang) * 0.5, 0, math.cos(ang) * 0.5),
        stone(),
      );
      tops.add(const V3(0, -1, 0));
      continue;
    }
    final t = V3(-math.sin(ang), 0, math.cos(ang));
    b.obox(
      c + const V3(0, 2.0, 0),
      t * 0.55,
      const V3(0, 2.0, 0),
      V3(math.cos(ang), 0, math.sin(ang)) * 0.35,
      stone(),
    );
    tops.add(c + const V3(0, 4.0, 0));
  }
  for (var i = 0; i < n; i++) {
    final p = tops[i], q = tops[(i + 1) % n];
    if (p.y < 0 || q.y < 0 || i % 3 == 2) continue;
    b.beam(p + const V3(0, 0.25, 0), q + const V3(0, 0.25, 0), 0.6, stone());
  }
  // Inner trilithons.
  for (var i = 0; i < 5; i++) {
    final ang = math.pi * (0.15 + i * 0.175) * 2 - math.pi * 0.2;
    final c = V3(math.cos(ang) * 3.2, 0, math.sin(ang) * 3.2);
    final t = V3(-math.sin(ang), 0, math.cos(ang));
    final h = 4.6 + (i == 2 ? 1.0 : 0);
    b.obox(
      c + t * 0.8 + V3(0, h / 2, 0),
      t * 0.45,
      V3(0, h / 2, 0),
      V3(math.cos(ang), 0, math.sin(ang)) * 0.4,
      stone(),
    );
    b.obox(
      c - t * 0.8 + V3(0, h / 2, 0),
      t * 0.45,
      V3(0, h / 2, 0),
      V3(math.cos(ang), 0, math.sin(ang)) * 0.4,
      stone(),
    );
    b.obox(
      c + V3(0, h + 0.3, 0),
      t * 1.4,
      const V3(0, 0.3, 0),
      V3(math.cos(ang), 0, math.sin(ang)) * 0.4,
      stone(),
    );
  }
  b.box(-1.2, 0, -0.4, 1.2, 0.5, 0.4, 0xFF8E897E);
}

void _windmillBody(MeshBuilder b) {
  const brick = 0xFF8A5A44, body = 0xFF4F463E, cap = 0xFF6B4F3A;
  b.lathe(0, 0, [0, 2.4], [4.4, 4.2], 8, brick, capTop: true, rot: math.pi / 8);
  b.lathe(
    0,
    0,
    [2.4, 13],
    [3.5, 2.1],
    8,
    body,
    capTop: false,
    rot: math.pi / 8,
  );
  // Gallery.
  b.lathe(
    0,
    0,
    [5.0, 5.3],
    [4.8, 4.8],
    8,
    0xFF6E5A48,
    capTop: true,
    capBottom: true,
    rot: math.pi / 8,
  );
  b.lathe(
    0,
    0,
    [12.8, 13.8, 14.8, 15.4],
    [2.6, 2.4, 1.6, 0.2],
    8,
    cap,
    capTop: false,
    rot: math.pi / 8,
  );
  b.wallRect(0, 1, 4.25, -0.7, 0.7, 0, 2.2, 0xFFF2EDE4, off: 0.1);
  b.mat = Mat.window;
  b.box(-0.45, 8, 2.55, 0.45, 9.2, 2.8, Pal.glass);
  b.mat = Mat.plain;
  b.cylinder(0, 2.2, 13.4, 13.4, 0.3, 6, Pal.darkMetal);
  b.beam(const V3(0, 13.4, 1.8), const V3(0, 13.4, 2.8), 0.5, Pal.darkMetal);
}

/// Four sails in the local XY plane, rotating around Z.
Mesh buildWindmillSails() {
  final b = MeshBuilder(sortParts: true);
  const wood = 0xFF5A4636, sail = 0xFFF1E9DA;
  for (var k = 0; k < 4; k++) {
    final a = k * math.pi / 2 + math.pi / 4;
    final dir = V3(math.cos(a), math.sin(a), 0);
    final side = V3(-math.sin(a), math.cos(a), 0);
    b.beam(const V3(0, 0, 0), dir * 10.5, 0.3, wood);
    final c = dir * 6.2 + side * 0.85;
    b.obox(c, dir * 4.2, side * 0.75, const V3(0, 0, 0.05), sail);
  }
  b.box(-0.5, -0.5, -0.4, 0.5, 0.5, 0.4, wood, bottom: true);
  return b.build();
}

void _moai(MeshBuilder b) {
  const ahu = 0xFF8C8478;
  b.box(-8, 0, -2.2, 8, 1.4, 2.2, ahu);
  final r = math.Random(3);
  for (var i = 0; i < 5; i++) {
    final x = -6.4 + i * 3.2;
    final c = [0xFF6F665C, 0xFF7A6F63, 0xFF645B52][r.nextInt(3)];
    final h = 6.5 + r.nextDouble() * 1.2;
    b.part();
    b.frustum(
      x - 1.0,
      -0.7,
      x + 1.0,
      0.7,
      1.4,
      1.4 + h * 0.45,
      0.12,
      c,
      insetZ: 0.05,
    );
    final y0 = 1.4 + h * 0.45;
    b.box(x - 0.85, y0, -0.65, x + 0.85, y0 + h * 0.55, 0.65, c);
    // Brow, nose, ears.
    b.box(x - 0.85, y0 + h * 0.4, 0.65, x + 0.85, y0 + h * 0.47, 0.95, c);
    b.frustum(
      x - 0.25,
      0.65,
      x + 0.25,
      1.3,
      y0 + h * 0.12,
      y0 + h * 0.4,
      0.05,
      c,
      insetZ: 0.2,
    );
    b.box(x - 0.95, y0 + h * 0.15, -0.2, x - 0.85, y0 + h * 0.42, 0.3, c);
    b.box(x + 0.85, y0 + h * 0.15, -0.2, x + 0.95, y0 + h * 0.42, 0.3, c);
    b.endPart();
    if (i.isOdd) {
      b.cylinder(x, 0, y0 + h * 0.55, y0 + h * 0.55 + 0.9, 0.75, 7, 0xFFA4483A);
    }
  }
}
