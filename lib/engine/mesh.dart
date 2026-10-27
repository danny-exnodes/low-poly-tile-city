import 'dart:math' as math;
import 'dart:typed_data';

/// Minimal immutable 3D vector used while building geometry.
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 operator -() => V3(-x, -y, -z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get normalized {
    final l = length;
    return l == 0 ? this : V3(x / l, y / l, z / l);
  }

  static const up = V3(0, 1, 0);
  static const down = V3(0, -1, 0);
}

/// Surface materials. The lighting pass uses these to apply seasons,
/// snow and night-time emissive effects.
abstract final class Mat {
  static const plain = 0;
  static const foliage = 1; // deciduous crown, hidden in winter
  static const grass = 2;
  static const window = 3; // glows at night
  static const roof = 4; // snow-covered in winter
  static const water = 5;
  static const lamp = 6; // glows at night
  static const conifer = 7; // evergreen, snow dusted in winter
  static const paved = 8; // lightly snowed in winter
  static const headlight = 9;
  static const crop = 10; // fields, follow seasons
  static const neon = 11; // signs / fair lights, glow at dusk
  static const branch = 12; // bare branches, only drawn in winter
}

/// Triangle soup with per-triangle normal, colour and material, grouped in
/// convex parts. Parts are drawn in build order unless [sortParts] is set,
/// in which case they are depth sorted every frame.
class Mesh {
  final Float32List pos; // 9 floats per triangle
  final Float32List nrm; // 3 floats per triangle
  final Int32List col;
  final Uint8List mat;
  final Int32List partStart; // parts + 1 entries
  final Float32List partBox; // 6 floats per part (min xyz, max xyz)
  final bool sortParts;
  final double minX, minY, minZ, maxX, maxY, maxZ;

  Mesh(
    this.pos,
    this.nrm,
    this.col,
    this.mat,
    this.partStart,
    this.partBox,
    this.sortParts,
    this.minX,
    this.minY,
    this.minZ,
    this.maxX,
    this.maxY,
    this.maxZ,
  );

  /// Simpler stand-in drawn when the object is smaller than [lodPx]
  /// pixels (projected radius) on screen (#4).
  Mesh? _lod;
  Mesh Function()? _makeLod;
  double lodPx = 0;

  /// The LOD mesh, built on first use (most houses are never far away).
  Mesh? get lod => _lod ??= _makeLod?.call();
  set lod(Mesh? m) => _lod = m;
  bool get hasLod => _lod != null || _makeLod != null;

  Uint8List? _ao;
  Int32List? _partRank;

  /// Construction order of each part (#6): bottom to top by the part's
  /// lowest point, ties kept in build order (decals stay with their wall).
  Int32List get partRank {
    final cached = _partRank;
    if (cached != null) return cached;
    final n = partCount;
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final ya = (partBox[a * 6 + 1] * 20).round();
        final yb = (partBox[b * 6 + 1] * 20).round();
        return ya != yb ? ya.compareTo(yb) : a.compareTo(b);
      });
    final rank = Int32List(n);
    for (var k = 0; k < n; k++) {
      rank[order[k]] = k;
    }
    return _partRank = rank;
  }

  /// Per-vertex ambient occlusion (3 per triangle, 255 = unoccluded),
  /// derived from the geometry once (#5): walls darken towards the ground
  /// and crowns darken underneath, which reads as soft, rounded volumes.
  Uint8List get ao => _ao ??= _computeAo();

  Uint8List _computeAo() {
    final n = triCount;
    final out = Uint8List(n * 3);
    var part = 0;
    for (var t = 0; t < n; t++) {
      while (part + 1 < partStart.length - 1 && partStart[part + 1] <= t) {
        part++;
      }
      final m = mat[t];
      final ny = nrm[t * 3 + 1];
      final foliage = m == Mat.foliage || m == Mat.conifer;
      final py0 = partBox.isEmpty ? minY : partBox[part * 6 + 1];
      final py1 = partBox.isEmpty ? maxY : partBox[part * 6 + 4];
      for (var v = 0; v < 3; v++) {
        final y = pos[t * 9 + v * 3 + 1];
        double a;
        if (foliage) {
          final h = py1 - py0;
          final k = h > 1e-3 ? ((y - py0) / h).clamp(0.0, 1.0) : 1.0;
          a = 0.6 + 0.4 * math.sqrt(k);
        } else if (ny.abs() < 0.7) {
          final k = ((y - minY) / 2.6).clamp(0.0, 1.0);
          a = 0.72 + 0.28 * k * k * (3 - 2 * k);
        } else {
          a = ny < 0 ? 0.75 : 1.0;
        }
        out[t * 3 + v] = (a * 255).round();
      }
    }
    return out;
  }

  /// Copy of this mesh without the triangles flagged in [skip].
  Mesh _without(Uint8List skip) {
    var keep = 0;
    for (final f in skip) {
      if (f == 0) keep++;
    }
    final p = Float32List(keep * 9), n = Float32List(keep * 3);
    final c = Int32List(keep), mt = Uint8List(keep);
    final ps = Int32List(partStart.length);
    var o = 0, pi = 0;
    for (var t = 0; t < triCount; t++) {
      while (pi < ps.length && partStart[pi] == t) {
        ps[pi++] = o;
      }
      if (skip[t] != 0) continue;
      p.setRange(o * 9, o * 9 + 9, pos, t * 9);
      n.setRange(o * 3, o * 3 + 3, nrm, t * 3);
      c[o] = col[t];
      mt[o] = mat[t];
      o++;
    }
    while (pi < ps.length) {
      ps[pi++] = o;
    }
    return Mesh(
      p,
      n,
      c,
      mt,
      ps,
      partBox,
      sortParts,
      minX,
      minY,
      minZ,
      maxX,
      maxY,
      maxZ,
    );
  }

  int get triCount => col.length;
  int get partCount => partStart.length - 1;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get centerZ => (minZ + maxZ) / 2;
  double get radius {
    final dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 2;
  }
}

class MeshBuilder {
  final _p = <double>[];
  final _n = <double>[];
  final _c = <int>[];
  final _m = <int>[];
  final _skip = <bool>[];

  /// Triangles added while true are left out of the LOD mesh.
  bool lodSkip = false;
  final _partStart = <int>[];
  final _partBox = <double>[];
  bool sortParts;

  /// Material applied to subsequently added triangles.
  int mat = Mat.plain;

  /// When false every primitive starts a new part automatically.
  bool _manualPart = false;

  MeshBuilder({this.sortParts = false});

  int get triCount => _c.length;

  /// Starts an explicit part: following primitives join it until
  /// [endPart] is called.
  void part() {
    _newPart();
    _manualPart = true;
  }

  void endPart() => _manualPart = false;

  void _newPart() {
    if (_partStart.isNotEmpty && _partStart.last == _c.length) return;
    _partStart.add(_c.length);
    _partBox.addAll(const [1e9, 1e9, 1e9, -1e9, -1e9, -1e9]);
  }

  void _autoPart() {
    if (!_manualPart || _partStart.isEmpty) _newPart();
  }

  void _grow(double x, double y, double z) {
    final b = _partBox.length - 6;
    if (x < _partBox[b]) _partBox[b] = x;
    if (y < _partBox[b + 1]) _partBox[b + 1] = y;
    if (z < _partBox[b + 2]) _partBox[b + 2] = z;
    if (x > _partBox[b + 3]) _partBox[b + 3] = x;
    if (y > _partBox[b + 4]) _partBox[b + 4] = y;
    if (z > _partBox[b + 5]) _partBox[b + 5] = z;
  }

  /// Adds a triangle facing [out] (a direction) or away from [center].
  void tri(V3 a, V3 b, V3 c, int color, {V3? out, V3? center}) {
    if (_partStart.isEmpty) _newPart();
    var n = (b - a).cross(c - a);
    final len = n.length;
    if (len < 1e-9) return;
    n = n * (1 / len);
    final dir =
        out ??
        (center != null
            ? V3(
                (a.x + b.x + c.x) / 3 - center.x,
                (a.y + b.y + c.y) / 3 - center.y,
                (a.z + b.z + c.z) / 3 - center.z,
              )
            : n);
    if (n.dot(dir) < 0) {
      final t = b;
      b = c;
      c = t;
      n = -n;
    }
    _p
      ..add(a.x)
      ..add(a.y)
      ..add(a.z)
      ..add(b.x)
      ..add(b.y)
      ..add(b.z)
      ..add(c.x)
      ..add(c.y)
      ..add(c.z);
    _n
      ..add(n.x)
      ..add(n.y)
      ..add(n.z);
    _c.add(color);
    _m.add(mat);
    _skip.add(lodSkip);
    _grow(a.x, a.y, a.z);
    _grow(b.x, b.y, b.z);
    _grow(c.x, c.y, c.z);
  }

  void quad(V3 a, V3 b, V3 c, V3 d, int color, {V3? out, V3? center}) {
    tri(a, b, c, color, out: out, center: center);
    tri(a, c, d, color, out: out, center: center);
  }

  /// Flat horizontal rectangle facing up.
  void flat(double x0, double z0, double x1, double z1, double y, int color) {
    _autoPart();
    quad(
      V3(x0, y, z0),
      V3(x1, y, z0),
      V3(x1, y, z1),
      V3(x0, y, z1),
      color,
      out: V3.up,
    );
  }

  /// Axis aligned box. Bottom face omitted unless [bottom] is true.
  void box(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    int color, {
    int? top,
    int? front,
    int? side,
    bool bottom = false,
    bool cap = true,
    double bevel = 0,
  }) {
    final r = math.min(bevel, math.min((x1 - x0), (z1 - z0)) * 0.3);
    if (r > 0.005 && !bottom) {
      _bevelBox(
        x0,
        y0,
        z0,
        x1,
        y1,
        z1,
        color,
        r,
        top: top,
        front: front,
        side: side,
        cap: cap,
      );
      return;
    }
    _autoPart();
    final c = V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    final s = side ?? color;
    if (cap) {
      quad(
        V3(x0, y1, z0),
        V3(x1, y1, z0),
        V3(x1, y1, z1),
        V3(x0, y1, z1),
        top ?? color,
        out: V3.up,
      );
    }
    if (bottom) {
      quad(
        V3(x0, y0, z0),
        V3(x1, y0, z0),
        V3(x1, y0, z1),
        V3(x0, y0, z1),
        color,
        out: V3.down,
      );
    }
    quad(
      V3(x0, y0, z1),
      V3(x1, y0, z1),
      V3(x1, y1, z1),
      V3(x0, y1, z1),
      front ?? color,
      center: c,
    );
    quad(
      V3(x0, y0, z0),
      V3(x1, y0, z0),
      V3(x1, y1, z0),
      V3(x0, y1, z0),
      color,
      center: c,
    );
    quad(
      V3(x0, y0, z0),
      V3(x0, y0, z1),
      V3(x0, y1, z1),
      V3(x0, y1, z0),
      s,
      center: c,
    );
    quad(
      V3(x1, y0, z0),
      V3(x1, y0, z1),
      V3(x1, y1, z1),
      V3(x1, y1, z0),
      s,
      center: c,
    );
  }

  static int _darker(int c) =>
      0xFF000000 |
      ((((c >> 16) & 255) * 7 ~/ 10) << 16) |
      ((((c >> 8) & 255) * 7 ~/ 10) << 8) |
      ((c & 255) * 7 ~/ 10);

  /// Box with chamfered vertical edges (and top edges when capped): the
  /// thin bevels catch light and soften the silhouette (#5).
  void _bevelBox(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    int color,
    double r, {
    int? top,
    int? front,
    int? side,
    bool cap = true,
  }) {
    _autoPart();
    final s = side ?? color, f = front ?? color, t = top ?? color;
    final yt = cap ? y1 - r : y1;
    // Faces: front (+z), back (-z), right (+x), left (-x).
    quad(
      V3(x0 + r, y0, z1),
      V3(x1 - r, y0, z1),
      V3(x1 - r, yt, z1),
      V3(x0 + r, yt, z1),
      f,
      out: const V3(0, 0, 1),
    );
    quad(
      V3(x0 + r, y0, z0),
      V3(x1 - r, y0, z0),
      V3(x1 - r, yt, z0),
      V3(x0 + r, yt, z0),
      color,
      out: const V3(0, 0, -1),
    );
    quad(
      V3(x1, y0, z0 + r),
      V3(x1, y0, z1 - r),
      V3(x1, yt, z1 - r),
      V3(x1, yt, z0 + r),
      s,
      out: const V3(1, 0, 0),
    );
    quad(
      V3(x0, y0, z0 + r),
      V3(x0, y0, z1 - r),
      V3(x0, yt, z1 - r),
      V3(x0, yt, z0 + r),
      s,
      out: const V3(-1, 0, 0),
    );
    // Vertical chamfers.
    for (final (sx, sz) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      final cx = sx > 0 ? x1 : x0, cz = sz > 0 ? z1 : z0;
      final a = V3(cx - sx * r, y0, cz), b = V3(cx, y0, cz - sz * r);
      quad(
        a,
        b,
        V3(b.x, yt, b.z),
        V3(a.x, yt, a.z),
        sz > 0 ? f : s,
        out: V3(sx.toDouble(), 0, sz.toDouble()),
      );
    }
    if (!cap) return;
    quad(
      V3(x0 + r, y1, z0 + r),
      V3(x1 - r, y1, z0 + r),
      V3(x1 - r, y1, z1 - r),
      V3(x0 + r, y1, z1 - r),
      t,
      out: V3.up,
    );
    // Top edge chamfers.
    quad(
      V3(x0 + r, yt, z1),
      V3(x1 - r, yt, z1),
      V3(x1 - r, y1, z1 - r),
      V3(x0 + r, y1, z1 - r),
      f,
      out: const V3(0, 1, 1),
    );
    quad(
      V3(x0 + r, yt, z0),
      V3(x1 - r, yt, z0),
      V3(x1 - r, y1, z0 + r),
      V3(x0 + r, y1, z0 + r),
      color,
      out: const V3(0, 1, -1),
    );
    quad(
      V3(x1, yt, z0 + r),
      V3(x1, yt, z1 - r),
      V3(x1 - r, y1, z1 - r),
      V3(x1 - r, y1, z0 + r),
      s,
      out: const V3(1, 1, 0),
    );
    quad(
      V3(x0, yt, z0 + r),
      V3(x0, yt, z1 - r),
      V3(x0 + r, y1, z1 - r),
      V3(x0 + r, y1, z0 + r),
      s,
      out: const V3(-1, 1, 0),
    );
    // Corner triangles.
    for (final (sx, sz) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      final cx = sx > 0 ? x1 : x0, cz = sz > 0 ? z1 : z0;
      tri(
        V3(cx - sx * r, yt, cz),
        V3(cx, yt, cz - sz * r),
        V3(cx - sx * r, y1, cz - sz * r),
        s,
        out: V3(sx.toDouble(), 1, sz.toDouble()),
      );
    }
  }

  /// Box centred at [c] with half-extent axes (any orientation).
  void obox(V3 c, V3 ax, V3 ay, V3 az, int color, {bool bottom = true}) {
    _autoPart();
    V3 p(int sx, int sy, int sz) =>
        c + ax * sx.toDouble() + ay * sy.toDouble() + az * sz.toDouble();
    quad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), color, center: c);
    if (bottom) {
      quad(
        p(-1, -1, -1),
        p(1, -1, -1),
        p(1, -1, 1),
        p(-1, -1, 1),
        color,
        center: c,
      );
    }
    quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), color, center: c);
    quad(
      p(-1, -1, -1),
      p(1, -1, -1),
      p(1, 1, -1),
      p(-1, 1, -1),
      color,
      center: c,
    );
    quad(
      p(-1, -1, -1),
      p(-1, -1, 1),
      p(-1, 1, 1),
      p(-1, 1, -1),
      color,
      center: c,
    );
    quad(p(1, -1, -1), p(1, -1, 1), p(1, 1, 1), p(1, 1, -1), color, center: c);
  }

  /// Box spanning from [a] to [b] with square cross-section of [w].
  void beam(V3 a, V3 b, double w, int color) {
    final d = b - a;
    final len = d.length;
    if (len < 1e-6) return;
    final az = d * (0.5 / len);
    var side = az.cross(V3.up);
    if (side.length < 1e-3) side = az.cross(const V3(1, 0, 0));
    final ax = side.normalized * (w / 2);
    final ay = ax.cross(az).normalized * (w / 2);
    obox((a + b) * 0.5, ax, ay, az * len, color);
  }

  /// Surface of revolution around the vertical axis at (cx, cz).
  /// [colors] optionally colours each ring band.
  void lathe(
    double cx,
    double cz,
    List<double> ys,
    List<double> rs,
    int segs,
    int color, {
    List<int>? colors,
    List<int>? segColors,
    bool capTop = true,
    bool capBottom = false,
    double rot = 0,
    double scaleZ = 1,
  }) {
    _autoPart();
    final cos = List<double>.generate(
      segs + 1,
      (i) => math.cos(rot + i * 2 * math.pi / segs),
    );
    final sin = List<double>.generate(
      segs + 1,
      (i) => math.sin(rot + i * 2 * math.pi / segs) * scaleZ,
    );
    for (var k = 0; k < ys.length - 1; k++) {
      final y0 = ys[k], y1 = ys[k + 1], r0 = rs[k], r1 = rs[k + 1];
      final dy = y1 - y0, dr = r1 - r0;
      final bandCol = colors != null ? colors[k % colors.length] : color;
      for (var i = 0; i < segs; i++) {
        final ma = rot + (i + 0.5) * 2 * math.pi / segs;
        final col = segColors != null
            ? segColors[(i + k) % segColors.length]
            : bandCol;
        final out = V3(math.cos(ma) * dy, -dr, math.sin(ma) * dy * scaleZ);
        final a = V3(cx + cos[i] * r0, y0, cz + sin[i] * r0);
        final b = V3(cx + cos[i + 1] * r0, y0, cz + sin[i + 1] * r0);
        final c = V3(cx + cos[i + 1] * r1, y1, cz + sin[i + 1] * r1);
        final d = V3(cx + cos[i] * r1, y1, cz + sin[i] * r1);
        if (r0 < 1e-6) {
          tri(a, c, d, col, out: out);
        } else if (r1 < 1e-6) {
          tri(a, b, c, col, out: out);
        } else {
          quad(a, b, c, d, col, out: out);
        }
      }
    }
    void cap(double y, double r, V3 out, int col) {
      if (r < 1e-6) return;
      final cc = V3(cx, y, cz);
      for (var i = 0; i < segs; i++) {
        tri(
          cc,
          V3(cx + cos[i] * r, y, cz + sin[i] * r),
          V3(cx + cos[i + 1] * r, y, cz + sin[i + 1] * r),
          col,
          out: out,
        );
      }
    }

    if (capTop) {
      cap(
        ys.last,
        rs.last,
        V3.up,
        colors != null ? colors[(ys.length - 2) % colors.length] : color,
      );
    }
    if (capBottom) cap(ys.first, rs.first, V3.down, color);
  }

  void cylinder(
    double cx,
    double cz,
    double y0,
    double y1,
    double r,
    int segs,
    int color, {
    bool capTop = true,
    double rot = 0,
  }) => lathe(cx, cz, [y0, y1], [r, r], segs, color, capTop: capTop, rot: rot);

  void cone(
    double cx,
    double cz,
    double y0,
    double y1,
    double r,
    int segs,
    int color, {
    double rot = 0,
    bool capBottom = false,
  }) => lathe(
    cx,
    cz,
    [y0, y1],
    [r, 0],
    segs,
    color,
    capTop: false,
    rot: rot,
    capBottom: capBottom,
  );

  void sphere(
    double cx,
    double cy,
    double cz,
    double r,
    int segs,
    int rings,
    int color, {
    double squash = 1,
  }) {
    final ys = <double>[], rs = <double>[];
    for (var i = 0; i <= rings; i++) {
      final t = math.pi * i / rings;
      ys.add(cy - math.cos(t) * r * squash);
      rs.add(math.sin(t) * r);
    }
    lathe(cx, cz, ys, rs, segs, color, capTop: false);
  }

  /// Geodesic sphere (icosahedron subdivided [subdiv] times). [wobble]
  /// nudges each shared vertex outward/inward for an organic, still
  /// watertight silhouette; [color] is asked once per triangle.
  void icosphere(
    V3 c,
    double r,
    int Function() color, {
    int subdiv = 1,
    double squash = 1,
    double Function()? wobble,
  }) {
    _autoPart();
    const t = 1.618033988749895;
    var verts = <V3>[
      const V3(-1, t, 0),
      const V3(1, t, 0),
      const V3(-1, -t, 0),
      const V3(1, -t, 0),
      const V3(0, -1, t),
      const V3(0, 1, t),
      const V3(0, -1, -t),
      const V3(0, 1, -t),
      const V3(t, 0, -1),
      const V3(t, 0, 1),
      const V3(-t, 0, -1),
      const V3(-t, 0, 1),
    ].map((v) => v.normalized).toList();
    var faces = <List<int>>[
      [0, 11, 5],
      [0, 5, 1],
      [0, 1, 7],
      [0, 7, 10],
      [0, 10, 11],
      [1, 5, 9],
      [5, 11, 4],
      [11, 10, 2],
      [10, 7, 6],
      [7, 1, 8],
      [3, 9, 4],
      [3, 4, 2],
      [3, 2, 6],
      [3, 6, 8],
      [3, 8, 9],
      [4, 9, 5],
      [2, 4, 11],
      [6, 2, 10],
      [8, 6, 7],
      [9, 8, 1],
    ];
    for (var s = 0; s < subdiv; s++) {
      final mid = <int, int>{};
      int m(int a, int b) {
        final k = a < b ? a * 65536 + b : b * 65536 + a;
        return mid.putIfAbsent(k, () {
          verts.add(((verts[a] + verts[b]) * 0.5).normalized);
          return verts.length - 1;
        });
      }

      faces = [
        for (final f in faces) ...[
          [f[0], m(f[0], f[1]), m(f[2], f[0])],
          [f[1], m(f[1], f[2]), m(f[0], f[1])],
          [f[2], m(f[2], f[0]), m(f[1], f[2])],
          [m(f[0], f[1]), m(f[1], f[2]), m(f[2], f[0])],
        ],
      ];
    }
    verts = [
      for (final v in verts)
        () {
          final k = r * (1 + (wobble?.call() ?? 0));
          return V3(c.x + v.x * k, c.y + v.y * k * squash, c.z + v.z * k);
        }(),
    ];
    for (final f in faces) {
      tri(verts[f[0]], verts[f[1]], verts[f[2]], color(), center: c);
    }
  }

  /// Arbitrary-axis cylinder between [a] and [b].
  void tube(V3 a, V3 b, double r, int segs, int color) {
    _autoPart();
    final d = b - a;
    final len = d.length;
    if (len < 1e-6) return;
    final az = d * (1 / len);
    var ax = az.cross(V3.up);
    if (ax.length < 1e-3) ax = az.cross(const V3(1, 0, 0));
    ax = ax.normalized;
    final ay = ax.cross(az);
    for (var i = 0; i < segs; i++) {
      final t0 = i * 2 * math.pi / segs, t1 = (i + 1) * 2 * math.pi / segs;
      final o0 = ax * (math.cos(t0) * r) + ay * (math.sin(t0) * r);
      final o1 = ax * (math.cos(t1) * r) + ay * (math.sin(t1) * r);
      final tm = (t0 + t1) / 2;
      final out = ax * math.cos(tm) + ay * math.sin(tm);
      quad(a + o0, a + o1, b + o1, b + o0, color, out: out);
    }
  }

  /// Rectangular frustum: bottom rect at y0, top rect inset by [inset].
  void frustum(
    double x0,
    double z0,
    double x1,
    double z1,
    double y0,
    double y1,
    double inset,
    int color, {
    int? top,
    bool cap = true,
    double insetZ = -1,
  }) {
    _autoPart();
    final iz = insetZ < 0 ? inset : insetZ;
    final c = V3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    final b0 = V3(x0, y0, z0), b1 = V3(x1, y0, z0);
    final b2 = V3(x1, y0, z1), b3 = V3(x0, y0, z1);
    final t0 = V3(x0 + inset, y1, z0 + iz), t1 = V3(x1 - inset, y1, z0 + iz);
    final t2 = V3(x1 - inset, y1, z1 - iz), t3 = V3(x0 + inset, y1, z1 - iz);
    quad(b0, b1, t1, t0, color, center: c);
    quad(b1, b2, t2, t1, color, center: c);
    quad(b2, b3, t3, t2, color, center: c);
    quad(b3, b0, t0, t3, color, center: c);
    if (cap) quad(t0, t1, t2, t3, top ?? color, out: V3.up);
  }

  /// Gable roof over a rectangle; ridge runs along x when [alongX].
  void gable(
    double x0,
    double z0,
    double x1,
    double z1,
    double y0,
    double h,
    int color, {
    int? gableColor,
    bool alongX = true,
    double overhang = 0.3,
  }) {
    _autoPart();
    final gc = gableColor ?? color;
    final c = V3((x0 + x1) / 2, y0 + h / 3, (z0 + z1) / 2);
    if (alongX) {
      final zm = (z0 + z1) / 2;
      final ox0 = x0 - overhang, ox1 = x1 + overhang;
      final oz0 = z0 - overhang, oz1 = z1 + overhang;
      final hy = y0 - overhang * h / ((z1 - z0) / 2);
      quad(
        V3(ox0, hy, oz0),
        V3(ox1, hy, oz0),
        V3(ox1, y0 + h, zm),
        V3(ox0, y0 + h, zm),
        color,
        center: c,
      );
      quad(
        V3(ox0, hy, oz1),
        V3(ox1, hy, oz1),
        V3(ox1, y0 + h, zm),
        V3(ox0, y0 + h, zm),
        color,
        center: c,
      );
      // Fascia boards under the eaves give the roof some thickness (#5).
      final fc = _darker(color);
      quad(
        V3(ox0, hy - 0.16, oz0),
        V3(ox1, hy - 0.16, oz0),
        V3(ox1, hy, oz0),
        V3(ox0, hy, oz0),
        fc,
        out: const V3(0, 0, -1),
      );
      quad(
        V3(ox0, hy - 0.16, oz1),
        V3(ox1, hy - 0.16, oz1),
        V3(ox1, hy, oz1),
        V3(ox0, hy, oz1),
        fc,
        out: const V3(0, 0, 1),
      );
      tri(
        V3(x0, y0, z0),
        V3(x0, y0, z1),
        V3(x0, y0 + h, zm),
        gc,
        out: const V3(-1, 0, 0),
      );
      tri(
        V3(x1, y0, z0),
        V3(x1, y0, z1),
        V3(x1, y0 + h, zm),
        gc,
        out: const V3(1, 0, 0),
      );
    } else {
      final xm = (x0 + x1) / 2;
      final ox0 = x0 - overhang, ox1 = x1 + overhang;
      final oz0 = z0 - overhang, oz1 = z1 + overhang;
      final hy = y0 - overhang * h / ((x1 - x0) / 2);
      quad(
        V3(ox0, hy, oz0),
        V3(ox0, hy, oz1),
        V3(xm, y0 + h, oz1),
        V3(xm, y0 + h, oz0),
        color,
        center: c,
      );
      quad(
        V3(ox1, hy, oz0),
        V3(ox1, hy, oz1),
        V3(xm, y0 + h, oz1),
        V3(xm, y0 + h, oz0),
        color,
        center: c,
      );
      final fc = _darker(color);
      quad(
        V3(ox0, hy - 0.16, oz0),
        V3(ox0, hy - 0.16, oz1),
        V3(ox0, hy, oz1),
        V3(ox0, hy, oz0),
        fc,
        out: const V3(-1, 0, 0),
      );
      quad(
        V3(ox1, hy - 0.16, oz0),
        V3(ox1, hy - 0.16, oz1),
        V3(ox1, hy, oz1),
        V3(ox1, hy, oz0),
        fc,
        out: const V3(1, 0, 0),
      );
      tri(
        V3(x0, y0, z0),
        V3(x1, y0, z0),
        V3(xm, y0 + h, z0),
        gc,
        out: const V3(0, 0, -1),
      );
      tri(
        V3(x0, y0, z1),
        V3(x1, y0, z1),
        V3(xm, y0 + h, z1),
        gc,
        out: const V3(0, 0, 1),
      );
    }
  }

  /// Hip roof (pyramid when square).
  void hip(
    double x0,
    double z0,
    double x1,
    double z1,
    double y0,
    double h,
    int color, {
    double overhang = 0.3,
  }) {
    _autoPart();
    x0 -= overhang;
    z0 -= overhang;
    x1 += overhang;
    z1 += overhang;
    final w = x1 - x0, d = z1 - z0;
    final c = V3((x0 + x1) / 2, y0, (z0 + z1) / 2);
    final top = y0 + h;
    V3 r0, r1;
    if (w >= d) {
      final zm = (z0 + z1) / 2, ins = d / 2;
      r0 = V3(x0 + ins, top, zm);
      r1 = V3(x1 - ins, top, zm);
    } else {
      final xm = (x0 + x1) / 2, ins = w / 2;
      r0 = V3(xm, top, z0 + ins);
      r1 = V3(xm, top, z1 - ins);
    }
    final b0 = V3(x0, y0, z0), b1 = V3(x1, y0, z0);
    final b2 = V3(x1, y0, z1), b3 = V3(x0, y0, z1);
    if (w >= d) {
      quad(b0, b1, r1, r0, color, center: c);
      quad(b3, b2, r1, r0, color, center: c);
      tri(b0, b3, r0, color, center: c);
      tri(b1, b2, r1, color, center: c);
    } else {
      quad(b0, b3, r1, r0, color, center: c);
      quad(b1, b2, r1, r0, color, center: c);
      tri(b0, b1, r0, color, center: c);
      tri(b3, b2, r1, color, center: c);
    }
  }

  /// A flat decal on a vertical wall. [nx],[nz] is the wall normal
  /// (axis aligned), [u] is the horizontal coordinate along the wall,
  /// [plane] the wall coordinate along the normal.
  void wallRect(
    int nx,
    int nz,
    double plane,
    double u0,
    double u1,
    double y0,
    double y1,
    int color, {
    double off = 0.04,
  }) {
    final out = V3(nx.toDouble(), 0, nz.toDouble());
    // Small decals vanish at a distance; lit windows stay for the night.
    final keep = lodSkip;
    lodSkip = mat != Mat.window;
    if (nx != 0) {
      final x = plane + nx * off;
      quad(
        V3(x, y0, u0),
        V3(x, y0, u1),
        V3(x, y1, u1),
        V3(x, y1, u0),
        color,
        out: out,
      );
    } else {
      final z = plane + nz * off;
      quad(
        V3(u0, y0, z),
        V3(u1, y0, z),
        V3(u1, y1, z),
        V3(u0, y1, z),
        color,
        out: out,
      );
    }
    lodSkip = keep;
  }

  /// Builds the mesh; with [lodPx] > 0 also attaches an LOD mesh without
  /// the triangles flagged [lodSkip].
  Mesh build({double lodPx = 0}) {
    final m = _build();
    if (lodPx > 0 && _skip.contains(true)) {
      final mask = Uint8List(_skip.length);
      for (var t = 0; t < mask.length; t++) {
        if (_skip[t]) mask[t] = 1;
      }
      m._makeLod = () => m._without(mask);
      m.lodPx = lodPx;
    }
    return m;
  }

  Mesh _build() {
    final p = _p, n = _n, c = _c, mt = _m;
    final ps = [..._partStart, _c.length];
    var mnx = 1e9, mny = 1e9, mnz = 1e9, mxx = -1e9, mxy = -1e9, mxz = -1e9;
    for (var i = 0; i < p.length; i += 3) {
      final x = p[i], y = p[i + 1], z = p[i + 2];
      if (x < mnx) mnx = x;
      if (y < mny) mny = y;
      if (z < mnz) mnz = z;
      if (x > mxx) mxx = x;
      if (y > mxy) mxy = y;
      if (z > mxz) mxz = z;
    }
    if (p.isEmpty) mnx = mny = mnz = mxx = mxy = mxz = 0;
    return Mesh(
      Float32List.fromList(p),
      Float32List.fromList(n),
      Int32List.fromList(c),
      Uint8List.fromList(mt),
      Int32List.fromList(ps),
      Float32List.fromList(_partBox),
      sortParts,
      mnx,
      mny,
      mnz,
      mxx,
      mxy,
      mxz,
    );
  }
}
