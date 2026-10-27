import 'dart:math' as math;
import 'dart:typed_data';

import 'lighting.dart';
import 'mesh.dart';

/// A mesh instance placed in the world.
class SceneObject {
  Mesh mesh;
  double x, y, z;
  double rot; // around Y
  double spin = 0; // around local Z (wheels, sails)
  double sx = 1, sy = 1, sz = 1;
  double shx = 0, shz = 0; // shear per unit height (wind sway)
  double tint;
  int key;
  bool visible = true;
  bool dynamicLight = false;
  bool castShadow;
  double highlight = 0;
  Object? owner;

  Int32List? lit;
  Int32List? lodLit;
  int lodLitVersion = -1;
  int litVersion = -1;

  SceneObject(
    this.mesh, {
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.rot = 0,
    this.tint = 0.5,
    this.key = 0,
    this.castShadow = true,
    this.owner,
  });

  /// Recomputes per-triangle lit colours when lighting changes.
  void relight(Light light) {
    lit = _shade(mesh, lit, light);
    litVersion = light.version;
  }

  /// Lit colours for the LOD mesh, computed when it is first drawn.
  void relightLod(Light light) {
    lodLit = _shade(mesh.lod!, lodLit, light);
    lodLitVersion = light.version;
  }

  Int32List _shade(Mesh m, Int32List? l, Light light) {
    final n = m.triCount;
    if (l == null || l.length != n) l = Int32List(n);
    final cr = math.cos(rot), sr = math.sin(rot);
    final cs = math.cos(spin), ss = math.sin(spin);
    final nrm = m.nrm, col = m.col, mat = m.mat;
    for (var i = 0; i < n; i++) {
      final nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
      final x1 = cs * nx - ss * ny, y1 = ss * nx + cs * ny;
      final wx = cr * x1 + sr * nz, wz = -sr * x1 + cr * nz;
      l[i] = light.shade(col[i], mat[i], wx, y1, wz, tint, key + (i >> 1));
    }
    return l;
  }
}

/// Particle kinds.
abstract final class PK {
  static const leaf = 0;
  static const snow = 1;
  static const dust = 2;
  static const petal = 3;
}

/// Struct-of-arrays particle pool (leaves, snow, dust).
class Particles {
  final int capacity;
  final Float32List x, y, z, vx, vy, vz, ang, angV, size, life, phase;
  final Int32List color;
  final Uint8List state; // 0 dead, 1 airborne, 2 resting
  final Uint8List kind;
  int count = 0; // high-water mark
  int alive = 0;

  Particles(this.capacity)
    : x = Float32List(capacity),
      y = Float32List(capacity),
      z = Float32List(capacity),
      vx = Float32List(capacity),
      vy = Float32List(capacity),
      vz = Float32List(capacity),
      ang = Float32List(capacity),
      angV = Float32List(capacity),
      size = Float32List(capacity),
      life = Float32List(capacity),
      phase = Float32List(capacity),
      color = Int32List(capacity),
      state = Uint8List(capacity),
      kind = Uint8List(capacity);

  int _cursor = 0;

  /// Returns a free slot or -1.
  int spawn() {
    for (var k = 0; k < capacity; k++) {
      final i = (_cursor + k) % capacity;
      if (state[i] == 0) {
        _cursor = i + 1;
        if (i >= count) count = i + 1;
        state[i] = 1;
        alive++;
        return i;
      }
    }
    return -1;
  }

  void kill(int i) {
    if (state[i] != 0) {
      state[i] = 0;
      alive--;
    }
  }

  void clear() {
    for (var i = 0; i < count; i++) {
      state[i] = 0;
    }
    count = 0;
    alive = 0;
  }
}

/// Everything the renderer needs for a frame.
class Scene {
  final objects = <SceneObject>[];

  /// Static ground geometry in world space: the board plus one object per
  /// block (roads, slabs, grass...).
  final groundObjects = <SceneObject>[];

  /// Optional outlined rectangle on the ground (x0, z0, x1, z1, y).
  List<double>? outline;

  /// Half extents of the board top, used to clip shadows.
  double boardHalfW = 100, boardHalfD = 100;

  /// Static shadow triangles on the ground (x,y,z * 3 per triangle).
  Float32List shadows = Float32List(0);

  /// Bumped whenever ground or shadows change.
  int groundVersion = 0;

  /// Objects that cast a small moving shadow (cars, people).
  final movers = <SceneObject>[];

  final particles = Particles(7000);

  Light light = Light(17.6, Season.autumn);

  /// Glowing point lights drawn at night (x, y, z triples).
  Float32List lamps = Float32List(0);
}
