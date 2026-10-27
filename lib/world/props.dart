import 'dart:math' as math;

import '../engine/mesh.dart';

/// Shared colour palette.
abstract final class Pal {
  static const asphalt = 0xFF55575D;
  static const asphaltDark = 0xFF4A4C52;
  static const marking = 0xFFE9E4D6;
  static const sidewalk = 0xFFD5CFC4;
  static const curb = 0xFFB9B2A6;
  static const board = 0xFFE8DCC8;
  static const boardSide = 0xFFCDBBA0;
  static const paving = 0xFFCFC3AE;
  static const pavingDark = 0xFFBFB29C;
  static const path = 0xFFD9C9A8;
  static const water = 0xFF5FA3C4;
  static const trunk = 0xFF6B4A35;
  static const glass = 0xFF3D4C60;
  static const glassLight = 0xFF6F8BA6;
  static const frame = 0xFFF1ECE2;
  static const door = 0xFF5A3B2A;
  static const metal = 0xFF8A9099;
  static const darkMetal = 0xFF4B5058;
  static const stone = 0xFFB8B0A2;
  static const skin = 0xFFE5B48E;

  static const facades = [
    0xFFF2E6D0,
    0xFFEEEAE2,
    0xFFE8C468,
    0xFFD9A25B,
    0xFFC56B4A,
    0xFFE3A6A0,
    0xFFE58F72,
    0xFFA9C4D6,
    0xFFB6C3A0,
    0xFFA0523D,
    0xFFB9B4AD,
    0xFFF0D9B5,
    0xFFE9D2C0,
    0xFF8FA9B8,
  ];
  static const roofs = [
    0xFF4A4E5A,
    0xFF3D4047,
    0xFFB5583A,
    0xFF7A4A35,
    0xFF5D6470,
    0xFFA34A33,
  ];
  static const cars = [
    0xFFD94436,
    0xFF3A6EA5,
    0xFFF2F0EA,
    0xFF2E3138,
    0xFFE8B931,
    0xFF6E9E6A,
    0xFF9AA3AD,
    0xFFE07B39,
    0xFF6D4C8F,
    0xFF4FA3A5,
  ];
  static const clothes = [
    0xFFD94436,
    0xFF3A6EA5,
    0xFFF2F0EA,
    0xFF2E3138,
    0xFFE8B931,
    0xFF6E9E6A,
    0xFFE07B39,
    0xFF9C5DA8,
    0xFF4FA3A5,
    0xFFB98B5E,
  ];
  static const awnings = [
    0xFFC9483B,
    0xFF2F7D5C,
    0xFF2F5D8C,
    0xFFE0A030,
    0xFF7D3C6B,
  ];
}

/// Tree styles selectable with "Switch trees".
enum TreeStyle { mixed, round, pine, cluster, poplar }

/// Builds the mesh for one tree species variant. Foliage triangles store a
/// brightness jitter in the red channel; the actual colour comes from the
/// season in the lighting pass.
Mesh buildTree(int species, int variant) {
  final r = math.Random(species * 31 + variant);
  final b = MeshBuilder();
  int jitter() => rgb8(r.nextInt(256));
  b.mat = Mat.plain;
  switch (species) {
    case 0: // round deciduous
      final h = 2.2 + r.nextDouble() * 0.6;
      b.cylinder(0, 0, 0, h + 0.6, 0.18, 5, Pal.trunk, capTop: false);
      _branches(b, h, r);
      b.mat = Mat.foliage;
      _blob(b, 0, h + 1.3, 0, 1.6 + r.nextDouble() * 0.4, r, jitter);
    case 1: // pine
      b.cylinder(0, 0, 0, 1.2, 0.2, 5, Pal.trunk, capTop: false);
      b.mat = Mat.conifer;
      final h = 4.5 + r.nextDouble() * 1.5;
      for (var k = 0; k < 3; k++) {
        final y0 = 0.9 + k * h * 0.26;
        final rad = 1.6 - k * 0.38;
        b.part();
        final segs = 6;
        final rot = r.nextDouble();
        for (var i = 0; i < segs; i++) {
          final a0 = rot + i * 2 * math.pi / segs;
          final a1 = rot + (i + 1) * 2 * math.pi / segs;
          b.tri(
            V3(math.cos(a0) * rad, y0, math.sin(a0) * rad),
            V3(math.cos(a1) * rad, y0, math.sin(a1) * rad),
            V3(0, y0 + h * 0.45, 0),
            jitter(),
            out: V3(math.cos((a0 + a1) / 2), 0.6, math.sin((a0 + a1) / 2)),
          );
        }
        b.endPart();
      }
    case 2: // poplar
      final h = 1.4 + r.nextDouble() * 0.4;
      b.cylinder(0, 0, 0, h + 1, 0.16, 5, Pal.trunk, capTop: false);
      _branches(b, h + 0.5, r);
      b.mat = Mat.foliage;
      b.part();
      final ys = [h, h + 1.2, h + 3.2, h + 4.8, h + 5.6];
      final rs = [0.0, 1.0, 1.15, 0.7, 0.0];
      _jitterLathe(b, ys, rs, 6, r, jitter);
      b.endPart();
    default: // cluster of chunky blobs (voxel-like)
      final h = 1.8 + r.nextDouble() * 0.5;
      b.cylinder(0, 0, 0, h + 0.8, 0.17, 5, Pal.trunk, capTop: false);
      _branches(b, h, r);
      b.mat = Mat.foliage;
      final n = 3 + r.nextInt(2);
      for (var k = 0; k < n; k++) {
        final a = k * 2 * math.pi / n + r.nextDouble();
        final d = k == 0 ? 0.0 : 0.7;
        final s = 0.75 + r.nextDouble() * 0.35;
        final cx = math.cos(a) * d, cz = math.sin(a) * d;
        final cy = h + 0.9 + r.nextDouble() * 0.8 + (k == 0 ? 0.7 : 0);
        b.box(cx - s, cy - s, cz - s, cx + s, cy + s, cz + s, jitter());
      }
  }
  final full = b.build();
  full.lod = _treeLod(full, species);
  full.lodPx = 11;
  return full;
}

/// Cheap stand-in for distant trees: a 3-sided trunk and an 8-triangle
/// crown spanning the full crown's bounds (#4).
Mesh _treeLod(Mesh full, int species) {
  var x0 = 1e9, y0 = 1e9, z0 = 1e9, x1 = -1e9, y1 = -1e9, z1 = -1e9;
  var mat = Mat.foliage;
  for (var t = 0; t < full.triCount; t++) {
    final m = full.mat[t];
    if (m != Mat.foliage && m != Mat.conifer) continue;
    mat = m;
    for (var v = 0; v < 3; v++) {
      final i = t * 9 + v * 3;
      x0 = math.min(x0, full.pos[i]);
      x1 = math.max(x1, full.pos[i]);
      y0 = math.min(y0, full.pos[i + 1]);
      y1 = math.max(y1, full.pos[i + 1]);
      z0 = math.min(z0, full.pos[i + 2]);
      z1 = math.max(z1, full.pos[i + 2]);
    }
  }
  final b = MeshBuilder();
  b.cylinder(0, 0, 0, y0 + 0.3, 0.2, 3, Pal.trunk, capTop: false);
  b.mat = mat;
  final cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
  final rx = (x1 - x0) / 2, rz = (z1 - z0) / 2;
  if (species == 1) {
    b.lathe(
      cx,
      cz,
      [y0, y1],
      [math.max(rx, rz), 0],
      4,
      rgb8(150),
      capTop: false,
    );
  } else {
    final my = species == 2 ? y0 + (y1 - y0) * 0.45 : (y0 + y1) / 2;
    b.lathe(
      cx,
      cz,
      [y0, my, y1],
      [0, math.max(rx, rz) * 0.95, 0],
      4,
      rgb8(150),
      colors: [rgb8(110), rgb8(200)],
      capTop: false,
      rot: math.pi / 4,
    );
  }
  return b.build();
}

int rgb8(int j) => 0xFF000000 | (j << 16) | (j << 8) | j;

void _branches(MeshBuilder b, double h, math.Random r) {
  // Bare branches: only drawn in winter, when foliage disappears.
  final m = b.mat;
  b.mat = Mat.branch;
  for (var k = 0; k < 3; k++) {
    final a = k * 2.1 + r.nextDouble();
    final y = h * (0.55 + 0.15 * k);
    b.beam(
      V3(0, y, 0),
      V3(math.cos(a) * 0.9, y + 1.0, math.sin(a) * 0.9),
      0.12,
      Pal.trunk,
    );
  }
  b.mat = m;
}

void _blob(
  MeshBuilder b,
  double cx,
  double cy,
  double cz,
  double rad,
  math.Random r,
  int Function() jitter,
) {
  b.part();
  const rings = 3, segs = 6;
  final ys = <double>[], rs = <double>[];
  for (var i = 0; i <= rings; i++) {
    final t = math.pi * i / rings;
    ys.add(cy - math.cos(t) * rad * 0.9);
    rs.add(math.sin(t) * rad * (0.9 + r.nextDouble() * 0.2));
  }
  _jitterLathe(b, ys, rs, segs, r, jitter, cx: cx, cz: cz);
  b.endPart();
}

void _jitterLathe(
  MeshBuilder b,
  List<double> ys,
  List<double> rs,
  int segs,
  math.Random r,
  int Function() jitter, {
  double cx = 0,
  double cz = 0,
}) {
  final rot = r.nextDouble();
  final center = V3(cx, (ys.first + ys.last) / 2, cz);
  for (var k = 0; k < ys.length - 1; k++) {
    for (var i = 0; i < segs; i++) {
      final a0 = rot + i * 2 * math.pi / segs + k * 0.5;
      final a1 = rot + (i + 1) * 2 * math.pi / segs + k * 0.5;
      final a2 = a0 + 0.5, a3 = a1 + 0.5;
      final p0 = V3(
        cx + math.cos(a0) * rs[k],
        ys[k],
        cz + math.sin(a0) * rs[k],
      );
      final p1 = V3(
        cx + math.cos(a1) * rs[k],
        ys[k],
        cz + math.sin(a1) * rs[k],
      );
      final p2 = V3(
        cx + math.cos(a3) * rs[k + 1],
        ys[k + 1],
        cz + math.sin(a3) * rs[k + 1],
      );
      final p3 = V3(
        cx + math.cos(a2) * rs[k + 1],
        ys[k + 1],
        cz + math.sin(a2) * rs[k + 1],
      );
      if (rs[k] < 1e-6) {
        b.tri(p0, p2, p3, jitter(), center: center);
      } else if (rs[k + 1] < 1e-6) {
        b.tri(p0, p1, p2, jitter(), center: center);
      } else {
        b.tri(p0, p1, p2, jitter(), center: center);
        b.tri(p0, p2, p3, jitter(), center: center);
      }
    }
  }
}

/// Car kinds: 0 sedan, 1 hatchback, 2 van, 3 bus, 4 taxi.
Mesh buildCar(int kind, int color) {
  final b = MeshBuilder();
  const wheel = 0xFF23252A;
  double len, wid, h1, h2, cab0, cab1;
  switch (kind) {
    case 2:
      len = 4.8;
      wid = 2.0;
      h1 = 1.0;
      h2 = 2.1;
      cab0 = -2.2;
      cab1 = 1.6;
    case 3:
      len = 10.5;
      wid = 2.5;
      h1 = 1.2;
      h2 = 3.0;
      cab0 = -5.1;
      cab1 = 5.1;
    case 1:
      len = 3.7;
      wid = 1.8;
      h1 = 0.85;
      h2 = 1.5;
      cab0 = -1.6;
      cab1 = 0.9;
    default:
      len = 4.4;
      wid = 1.85;
      h1 = 0.85;
      h2 = 1.45;
      cab0 = -1.1;
      cab1 = 1.0;
  }
  final hl = len / 2, hw = wid / 2;
  // Wheels (simple dark blocks).
  for (final wz in [-hl * 0.62, hl * 0.62]) {
    b.box(-hw - 0.02, 0, wz - 0.35, -hw + 0.3, 0.6, wz + 0.35, wheel);
    b.box(hw - 0.3, 0, wz - 0.35, hw + 0.02, 0.6, wz + 0.35, wheel);
  }
  b.part();
  b.box(-hw, 0.3, -hl, hw, h1, hl, color);
  // Lights.
  b.mat = Mat.headlight;
  b.wallRect(
    0,
    1,
    hl,
    -hw + 0.15,
    -hw + 0.55,
    h1 - 0.35,
    h1 - 0.12,
    0xFFF4F0DC,
  );
  b.wallRect(0, 1, hl, hw - 0.55, hw - 0.15, h1 - 0.35, h1 - 0.12, 0xFFF4F0DC);
  b.mat = Mat.plain;
  b.wallRect(
    0,
    -1,
    -hl,
    -hw + 0.15,
    -hw + 0.5,
    h1 - 0.35,
    h1 - 0.12,
    0xFFB52D2D,
  );
  b.wallRect(0, -1, -hl, hw - 0.5, hw - 0.15, h1 - 0.35, h1 - 0.12, 0xFFB52D2D);
  b.endPart();
  // Cabin.
  b.part();
  final inset = kind == 3 ? 0.05 : 0.12;
  b.frustum(
    -hw + inset,
    cab0,
    hw - inset,
    cab1,
    h1,
    h2,
    kind >= 2 ? 0.05 : 0.18,
    kind == 3 ? color : Pal.glass,
    top: color,
    insetZ: kind >= 2 ? 0.05 : 0.45,
  );
  if (kind == 3) {
    // Bus window band.
    b.wallRect(
      1,
      0,
      hw - inset,
      cab0 + 0.4,
      cab1 - 0.4,
      h1 + 0.5,
      h2 - 0.4,
      Pal.glass,
    );
    b.wallRect(
      -1,
      0,
      -hw + inset,
      cab0 + 0.4,
      cab1 - 0.4,
      h1 + 0.5,
      h2 - 0.4,
      Pal.glass,
    );
    b.wallRect(0, 1, cab1, -hw + 0.2, hw - 0.2, h1 + 0.5, h2 - 0.3, Pal.glass);
  } else if (kind == 2) {
    b.wallRect(
      0,
      1,
      cab1,
      -hw + 0.2,
      hw - 0.2,
      h1 + 0.35,
      h2 - 0.25,
      Pal.glass,
    );
  }
  if (kind == 4) {
    b.box(-0.3, h2, -0.2, 0.3, h2 + 0.25, 0.2, 0xFFF7F3E0);
  }
  b.endPart();
  return b.build();
}

Mesh buildPerson(int shirt, int pants, int hair) {
  final b = MeshBuilder();
  b.box(-0.2, 0, -0.12, -0.02, 0.85, 0.12, pants);
  b.box(0.02, 0, -0.12, 0.2, 0.85, 0.12, pants);
  b.box(-0.26, 0.85, -0.15, 0.26, 1.45, 0.15, shirt);
  b.box(-0.14, 1.45, -0.14, 0.14, 1.75, 0.14, Pal.skin, top: hair);
  return b.build();
}

Mesh buildLamp() {
  final b = MeshBuilder();
  b.cylinder(0, 0, 0, 4.2, 0.08, 4, Pal.darkMetal);
  b.beam(const V3(0, 4.1, 0), const V3(0.9, 4.25, 0), 0.1, Pal.darkMetal);
  b.mat = Mat.lamp;
  b.box(
    0.65,
    3.95,
    -0.18,
    1.15,
    4.15,
    0.18,
    0xFFE8E2CC,
    top: Pal.darkMetal,
    bottom: true,
  );
  return b.build();
}

Mesh buildBench() {
  final b = MeshBuilder();
  b.box(-0.9, 0, -0.25, -0.8, 0.45, 0.25, Pal.darkMetal);
  b.box(0.8, 0, -0.25, 0.9, 0.45, 0.25, Pal.darkMetal);
  b.box(-1.0, 0.45, -0.3, 1.0, 0.55, 0.3, 0xFF8C5E3C);
  b.box(-1.0, 0.55, 0.22, 1.0, 1.0, 0.3, 0xFF8C5E3C);
  return b.build();
}

Mesh buildFountain(double r) {
  final b = MeshBuilder();
  b.lathe(0, 0, [0, 0.6, 0.6], [r, r, r - 0.4], 10, Pal.stone, capTop: false);
  b.mat = Mat.water;
  b.lathe(0, 0, [0.5, 0.5], [r - 0.4, 0], 10, Pal.water, capTop: false);
  b.mat = Mat.plain;
  b.lathe(0, 0, [0.5, 1.6, 1.8, 2.0], [0.35, 0.25, 1.1, 0.9], 8, Pal.stone);
  b.mat = Mat.water;
  b.lathe(0, 0, [1.9, 2.7, 3.2], [0.6, 0.25, 0], 6, 0xFF9BCBE0);
  return b.build();
}
