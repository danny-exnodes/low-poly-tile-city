import 'dart:math' as math;

import '../engine/lighting.dart';
import '../engine/mesh.dart';
import '../engine/scene.dart';
import 'city.dart';
import 'props.dart';

const _dx = [1, 0, -1, 0];
const _dz = [0, 1, 0, -1];
const _lane = 2.4;

class Car {
  final SceneObject obj;
  int ni, nj, dir;
  double s = 0;
  double speed;
  final double cruise;
  bool turning = false;
  double t = 0, turnLen = 1;
  int nextDir = 0;
  double p0x = 0, p0z = 0, p1x = 0, p1z = 0, p2x = 0, p2z = 0;
  Car(this.obj, this.ni, this.nj, this.dir, this.cruise) : speed = cruise;
}

class Person {
  final SceneObject obj;
  final Block block;
  double s;
  final double dir, inset, speed, phase;
  Person(
    this.obj,
    this.block,
    this.s,
    this.dir,
    this.inset,
    this.speed,
    this.phase,
  );
}

/// Cars driving the road grid and people strolling on sidewalks.
class Traffic {
  final cars = <Car>[];
  final people = <Person>[];
  final _r = math.Random(42);
  final _carMeshes = <int, Mesh>{};
  final _peopleMeshes = <Mesh>[];

  Mesh _carMesh(int kind, int color) => _carMeshes.putIfAbsent(
    kind * 0x1000000 + (color & 0xFFFFFF),
    () => buildCar(kind, color),
  );

  void clear(Scene scene) {
    for (final c in cars) {
      scene.objects.remove(c.obj);
      scene.movers.remove(c.obj);
    }
    for (final p in people) {
      scene.objects.remove(p.obj);
      scene.movers.remove(p.obj);
    }
    cars.clear();
    people.clear();
  }

  /// Adjusts the number of cars and people to the slider.
  double amount = 1;

  void populate(Scene scene, City city) {
    final blocks = city.nx * city.nz;
    final wantCars = (blocks * 1.5 * amount).round();
    final wantPeople = (blocks * 3.0 * amount).round();
    while (cars.length > wantCars) {
      final c = cars.removeLast();
      scene.objects.remove(c.obj);
      scene.movers.remove(c.obj);
    }
    while (cars.length < wantCars) {
      final roll = _r.nextDouble();
      final kind = roll < 0.45
          ? 0
          : roll < 0.75
          ? 1
          : roll < 0.85
          ? 2
          : roll < 0.95
          ? 4
          : 3;
      final color = kind == 4
          ? 0xFFF2C230
          : kind == 3
          ? 0xFFD8402F
          : Pal.cars[_r.nextInt(Pal.cars.length)];
      final o = SceneObject(_carMesh(kind, color), key: 5000 + cars.length * 13)
        ..dynamicLight = true
        ..castShadow = false;
      // Random edge.
      int ni, nj, dir;
      while (true) {
        ni = _r.nextInt(city.nx + 1);
        nj = _r.nextInt(city.nz + 1);
        dir = _r.nextInt(4);
        final ti = ni + _dx[dir], tj = nj + _dz[dir];
        if (ti >= 0 && tj >= 0 && ti <= city.nx && tj <= city.nz) break;
      }
      final c = Car(
        o,
        ni,
        nj,
        dir,
        (kind == 3 ? 6.0 : 8.0) + _r.nextDouble() * 4,
      );
      c.s = _r.nextDouble() * (City.pitch - City.road);
      cars.add(c);
      scene.objects.add(o);
      scene.movers.add(o);
      _placeCar(c, city);
    }

    while (people.length > wantPeople) {
      final p = people.removeLast();
      scene.objects.remove(p.obj);
      scene.movers.remove(p.obj);
    }
    if (_peopleMeshes.isEmpty) {
      for (var k = 0; k < 16; k++) {
        _peopleMeshes.add(
          buildPerson(
            Pal.clothes[_r.nextInt(Pal.clothes.length)],
            const [0xFF2E3138, 0xFF3A4A6A, 0xFF6B5A48, 0xFF8A8F96][_r.nextInt(
              4,
            )],
            const [0xFF2B1D14, 0xFF6B4A2A, 0xFFD9B26A, 0xFF8A8A8A][_r.nextInt(
              4,
            )],
          ),
        );
      }
    }
    while (people.length < wantPeople && city.blocks.isNotEmpty) {
      final b = city.blocks[_r.nextInt(city.blocks.length)];
      final o =
          SceneObject(
              _peopleMeshes[_r.nextInt(_peopleMeshes.length)],
              key: 9000 + people.length,
            )
            ..dynamicLight = true
            ..castShadow = false;
      final inset = _r.nextBool() ? 0.7 : 2.4;
      final p = Person(
        o,
        b,
        _r.nextDouble() * 400,
        _r.nextBool() ? 1 : -1,
        inset,
        1.0 + _r.nextDouble() * 0.6,
        _r.nextDouble() * 6,
      );
      people.add(p);
      scene.objects.add(o);
      scene.movers.add(o);
    }
  }

  /// Re-attaches people to blocks after the city was rebuilt.
  void rehome(Scene scene, City city) {
    final n = people.length;
    for (final p in people) {
      scene.objects.remove(p.obj);
      scene.movers.remove(p.obj);
    }
    people.clear();
    for (final c in cars) {
      if (!scene.objects.contains(c.obj)) {
        scene.objects.add(c.obj);
        scene.movers.add(c.obj);
      }
    }
    // Drop cars whose edge left the grid.
    cars.removeWhere((c) {
      final ti = c.ni + _dx[c.dir], tj = c.nj + _dz[c.dir];
      final bad =
          c.ni > city.nx ||
          c.nj > city.nz ||
          ti < 0 ||
          tj < 0 ||
          ti > city.nx ||
          tj > city.nz;
      if (bad) {
        scene.objects.remove(c.obj);
        scene.movers.remove(c.obj);
      }
      return bad;
    });
    if (n >= 0) populate(scene, city);
  }

  void _placeCar(Car c, City city) {
    final o = c.obj;
    if (!c.turning) {
      final d = c.dir;
      final bx = city.nodeX(c.ni), bz = city.nodeZ(c.nj);
      final along = City.road / 2 + c.s;
      o.x = bx + _dx[d] * along - _dz[d] * _lane;
      o.z = bz + _dz[d] * along + _dx[d] * _lane;
      o.rot = math.atan2(_dx[d].toDouble(), _dz[d].toDouble());
    } else {
      final t = c.t, u = 1 - t;
      o.x = u * u * c.p0x + 2 * u * t * c.p1x + t * t * c.p2x;
      o.z = u * u * c.p0z + 2 * u * t * c.p1z + t * t * c.p2z;
      final tx = 2 * u * (c.p1x - c.p0x) + 2 * t * (c.p2x - c.p1x);
      final tz = 2 * u * (c.p1z - c.p0z) + 2 * t * (c.p2z - c.p1z);
      o.rot = math.atan2(tx, tz);
    }
    o.y = 0;
  }

  void update(double dt, City city, double time) {
    final segLen = City.pitch - City.road;
    // Simple car following on the same edge.
    for (final c in cars) {
      var target = c.cruise;
      if (!c.turning) {
        for (final o in cars) {
          if (identical(o, c) || o.turning) continue;
          if (o.ni == c.ni && o.nj == c.nj && o.dir == c.dir) {
            final gap = o.s - c.s;
            if (gap > 0 && gap < 9) {
              target = math.min(target, math.max(0, (gap - 5) * 1.5));
            }
          }
        }
        // Slow down approaching the intersection.
        if (c.s > segLen - 8) target = math.min(target, 5.5);
      } else {
        target = math.min(target, 5.0);
      }
      c.speed += (target - c.speed) * math.min(1, dt * 2.5);
    }
    for (final c in cars) {
      if (!c.turning) {
        c.s += c.speed * dt;
        if (c.s >= segLen) {
          // Arrive at next node: pick a new direction.
          final ni = c.ni + _dx[c.dir], nj = c.nj + _dz[c.dir];
          final opts = <int>[];
          for (var d = 0; d < 4; d++) {
            if (d == (c.dir + 2) % 4) continue;
            final ti = ni + _dx[d], tj = nj + _dz[d];
            if (ti < 0 || tj < 0 || ti > city.nx || tj > city.nz) continue;
            opts.add(d);
            if (d == c.dir) opts.add(d); // prefer straight
          }
          if (opts.isEmpty) opts.add((c.dir + 2) % 4);
          final nd = opts[_r.nextInt(opts.length)];
          final bx = city.nodeX(ni), bz = city.nodeZ(nj);
          const h = City.road / 2;
          final d = c.dir;
          c.p0x = bx - _dx[d] * h - _dz[d] * _lane;
          c.p0z = bz - _dz[d] * h + _dx[d] * _lane;
          c.p2x = bx + _dx[nd] * h - _dz[nd] * _lane;
          c.p2z = bz + _dz[nd] * h + _dx[nd] * _lane;
          if (nd == d) {
            c.p1x = (c.p0x + c.p2x) / 2;
            c.p1z = (c.p0z + c.p2z) / 2;
          } else if (nd == (d + 2) % 4) {
            c.p1x = bx + _dx[d] * h;
            c.p1z = bz + _dz[d] * h;
          } else {
            c.p1x = bx + (-_dz[d] - _dz[nd]) * _lane;
            c.p1z = bz + (_dx[d] + _dx[nd]) * _lane;
          }
          c.turnLen = math.max(
            2,
            math.sqrt(math.pow(c.p1x - c.p0x, 2) + math.pow(c.p1z - c.p0z, 2)) +
                math.sqrt(
                  math.pow(c.p2x - c.p1x, 2) + math.pow(c.p2z - c.p1z, 2),
                ),
          );
          c.turning = true;
          c.t = 0;
          c.nextDir = nd;
          c.ni = ni;
          c.nj = nj;
        }
      } else {
        c.t += c.speed * dt / c.turnLen;
        if (c.t >= 1) {
          c.turning = false;
          c.dir = c.nextDir;
          c.s = 0;
        }
      }
      _placeCar(c, city);
    }

    // People walk around their block.
    for (final p in people) {
      final b = p.block;
      final side = City.block - 2 * p.inset;
      final per = side * 4;
      p.s = (p.s + p.dir * p.speed * dt) % per;
      if (p.s < 0) p.s += per;
      final seg = (p.s / side).floor();
      final u = p.s - seg * side;
      final x0 = b.x0 + p.inset, z0 = b.z0 + p.inset;
      double x, z, hx, hz;
      switch (seg) {
        case 0:
          x = x0 + u;
          z = z0;
          hx = 1;
          hz = 0;
        case 1:
          x = x0 + side;
          z = z0 + u;
          hx = 0;
          hz = 1;
        case 2:
          x = x0 + side - u;
          z = z0 + side;
          hx = -1;
          hz = 0;
        default:
          x = x0;
          z = z0 + side - u;
          hx = 0;
          hz = -1;
      }
      final o = p.obj;
      o.x = x;
      o.z = z;
      o.y = 0.3 + (math.sin(time * 8 * p.speed + p.phase)).abs() * 0.06;
      o.rot = math.atan2(hx * p.dir, hz * p.dir);
    }
  }
}

/// Wind state with gusts and noise.
class Wind {
  double base = 5;
  double fromDeg = 315; // north-west
  double gust = 0; // remaining gust time
  double speed = 5;
  double vx = 0, vz = 0;

  static const gustLen = 5.0;

  void update(double dt, double t) {
    final noise =
        1 +
        0.22 * math.sin(t * 0.63) +
        0.12 * math.sin(t * 1.71 + 1.3) +
        0.06 * math.sin(t * 4.1 + 0.2);
    var s = base * noise;
    if (gust > 0) {
      gust = math.max(0, gust - dt);
      final k = math.sin(math.pi * (1 - gust / gustLen));
      s += math.max(9.0, base * 1.4) * k;
    }
    speed = math.max(0, s);
    final a = fromDeg * math.pi / 180;
    // "From" direction: north is -z, east is +x. Wind blows the other way.
    vx = -math.sin(a) * speed;
    vz = math.cos(a) * speed;
  }

  String get compassName {
    const names = [
      'North',
      'North-East',
      'East',
      'South-East',
      'South',
      'South-West',
      'West',
      'North-West',
    ];
    return names[((fromDeg % 360) / 45).round() % 8];
  }

  static String beaufort(double s) {
    if (s < 2.5) return 'CALM';
    if (s < 5) return 'LIGHT BREEZE';
    if (s < 8) return 'GENTLE BREEZE';
    if (s < 11) return 'MODERATE';
    if (s < 14) return 'FRESH';
    if (s < 17) return 'STRONG';
    return 'GALE';
  }
}

/// Leaf devil: a small whirlwind crossing the town.
class LeafDevil {
  double x, z, vx, vz, life;
  LeafDevil(this.x, this.z, this.vx, this.vz, this.life);
  static const radius = 9.0;
}

/// Falling leaves, snow, petals and dust.
class Weather {
  final _r = math.Random(7);
  LeafDevil? devil;
  double leaves = 1.0; // spawn multiplier
  double leafSize = 1.6;
  double _acc = 0;

  void startDevil(City city, Wind wind) {
    // Enter from the windward side and cross near the centre.
    final w = city.width / 2, d = city.depth / 2;
    final a = _r.nextDouble() * math.pi * 2;
    final sx = math.cos(a) * w * 0.8, sz = math.sin(a) * d * 0.8;
    final tx = (_r.nextDouble() - 0.5) * w * 0.4;
    final tz = (_r.nextDouble() - 0.5) * d * 0.4;
    final len = math.sqrt((tx - sx) * (tx - sx) + (tz - sz) * (tz - sz));
    const sp = 7.0;
    devil = LeafDevil(
      sx,
      sz,
      (tx - sx) / len * sp,
      (tz - sz) / len * sp,
      2 * len / sp,
    );
  }

  int _spawnLeaf(
    Particles p,
    double x,
    double y,
    double z,
    int color,
    int kind,
  ) {
    final i = p.spawn();
    if (i < 0) return i;
    p.x[i] = x;
    p.y[i] = y;
    p.z[i] = z;
    p.vx[i] = 0;
    p.vy[i] = kind == PK.snow ? -1.2 : -0.4;
    p.vz[i] = 0;
    p.ang[i] = _r.nextDouble() * 6.28;
    p.angV[i] = (_r.nextDouble() - 0.5) * 6;
    p.phase[i] = _r.nextDouble() * 6.28;
    final base = kind == PK.snow
        ? 0.16
        : kind == PK.petal
        ? 0.2
        : 0.3;
    p.size[i] = base * leafSize * (0.8 + _r.nextDouble() * 0.4);
    p.color[i] = color;
    p.kind[i] = kind;
    p.life[i] = 60;
    return i;
  }

  void dust(Particles p, double x, double y, double z, int n) {
    for (var k = 0; k < n; k++) {
      final i = p.spawn();
      if (i < 0) return;
      final a = _r.nextDouble() * 6.28;
      final r = 2 + _r.nextDouble() * 5;
      p.x[i] = x + math.cos(a) * r;
      p.y[i] = y + _r.nextDouble() * 2;
      p.z[i] = z + math.sin(a) * r;
      p.vx[i] = math.cos(a) * 1.5;
      p.vy[i] = 0.6 + _r.nextDouble();
      p.vz[i] = math.sin(a) * 1.5;
      p.ang[i] = a;
      p.angV[i] = 0.5;
      p.phase[i] = 1.57;
      p.size[i] = 0.6 + _r.nextDouble() * 0.7;
      p.color[i] = const [0xFFD8CCB8, 0xFFC9BCA6, 0xFFE6DCCB][_r.nextInt(3)];
      p.kind[i] = PK.dust;
      p.life[i] = 1.2 + _r.nextDouble() * 0.8;
    }
  }

  void update(double dt, double t, Scene scene, City city, Wind wind) {
    final p = scene.particles;
    final light = scene.light;
    final season = light.season;

    // Spawning.
    var rate = 0.0;
    final gusting = wind.gust > 0;
    final windF = 0.35 + wind.speed / 6;
    switch (season) {
      case Season.autumn:
        rate = leaves * 0.1 * windF * (gusting ? 4 : 1);
      case Season.summer:
        rate = leaves * 0.004 * windF * (gusting ? 4 : 1);
      case Season.spring:
        rate = leaves * 0.03 * windF;
      case Season.winter:
        rate = 0;
    }
    if (rate > 0 && city.trees.isNotEmpty) {
      _acc += rate * city.trees.length * dt;
      var guard = 0;
      while (_acc >= 1 && guard++ < 200) {
        _acc -= 1;
        final tr = city.trees[_r.nextInt(city.trees.length)];
        if (!tr.deciduous || !tr.obj.visible) continue;
        if (season == Season.spring && tr.obj.tint >= 0.22) continue;
        final a = _r.nextDouble() * 6.28, rr = _r.nextDouble() * tr.crownR;
        final o = tr.obj;
        _spawnLeaf(
          p,
          o.x + math.cos(a) * rr + o.shx * tr.crownY,
          tr.crownY + (_r.nextDouble() - 0.3) * tr.crownR,
          o.z + math.sin(a) * rr + o.shz * tr.crownY,
          light.leafParticle(
            season == Season.spring ? o.tint : _r.nextDouble(),
          ),
          season == Season.spring ? PK.petal : PK.leaf,
        );
      }
    } else if (season == Season.winter) {
      _acc += leaves * 0.0018 * city.width * city.depth * dt * 0.5;
      var guard = 0;
      while (_acc >= 1 && guard++ < 300) {
        _acc -= 1;
        _spawnLeaf(
          p,
          (_r.nextDouble() - 0.5) * city.width * 1.1,
          28 + _r.nextDouble() * 22,
          (_r.nextDouble() - 0.5) * city.depth * 1.1,
          0xFFF4F7FB,
          PK.snow,
        );
      }
    } else {
      _acc = 0;
    }

    // Leaf devil.
    final dv = devil;
    if (dv != null) {
      dv.x += dv.vx * dt;
      dv.z += dv.vz * dt;
      dv.life -= dt;
      if (dv.life <= 0) devil = null;
      // Feed it with some leaves so it is always visible.
      final n = (dt * 40).ceil();
      for (var k = 0; k < n; k++) {
        final a = _r.nextDouble() * 6.28, rr = _r.nextDouble() * 4;
        final c = season == Season.winter
            ? 0xFFF4F7FB
            : light.leafParticle(_r.nextDouble());
        final i = _spawnLeaf(
          p,
          dv.x + math.cos(a) * rr,
          0.5,
          dv.z + math.sin(a) * rr,
          c,
          season == Season.winter ? PK.snow : PK.leaf,
        );
        if (i >= 0) p.vy[i] = 2;
      }
    }

    // Integration.
    final wx = wind.vx, wz = wind.vz;
    final lift = wind.speed > 8.5;
    for (var i = 0; i < p.count; i++) {
      final st = p.state[i];
      if (st == 0) continue;
      final kind = p.kind[i];
      if (kind == PK.dust) {
        p.life[i] -= dt;
        if (p.life[i] <= 0) {
          p.kill(i);
          continue;
        }
        p.x[i] += p.vx[i] * dt;
        p.y[i] += p.vy[i] * dt;
        p.z[i] += p.vz[i] * dt;
        p.size[i] += dt * 0.8;
        continue;
      }
      if (st == 2) {
        p.life[i] -= dt;
        if (p.life[i] <= 0) {
          p.kill(i);
          continue;
        }
        var liftNow = false;
        if (kind != PK.snow) {
          if (lift && _r.nextDouble() < dt * 0.25 * (wind.speed - 8.5) / 4) {
            liftNow = true;
          }
          if (dv != null) {
            final ddx = p.x[i] - dv.x, ddz = p.z[i] - dv.z;
            if (ddx * ddx + ddz * ddz < LeafDevil.radius * LeafDevil.radius &&
                _r.nextDouble() < dt * 3) {
              liftNow = true;
            }
          }
        }
        if (liftNow) {
          p.state[i] = 1;
          p.vy[i] = 1.5 + _r.nextDouble() * 2.5;
          p.y[i] += 0.1;
          p.life[i] = 60;
        }
        continue;
      }
      // Airborne.
      final ph = p.phase[i];
      final turbX =
          math.sin(t * 1.3 + ph * 5) * 0.9 + math.sin(t * 3.1 + ph) * 0.4;
      final turbZ =
          math.cos(t * 1.1 + ph * 3) * 0.9 + math.cos(t * 2.7 + ph) * 0.4;
      final drag = kind == PK.snow ? 0.8 : 1.6;
      var tvx = wx * 0.8 + turbX, tvz = wz * 0.8 + turbZ;
      var tvy = kind == PK.snow ? -1.1 : -0.85 + math.sin(ph * 2) * 0.5;
      if (dv != null) {
        final ddx = p.x[i] - dv.x, ddz = p.z[i] - dv.z;
        final d2 = ddx * ddx + ddz * ddz;
        const rr = LeafDevil.radius * 1.4;
        if (d2 < rr * rr) {
          final d = math.sqrt(d2) + 0.3;
          final k = 1 - d / rr;
          tvx = dv.vx + (-ddz / d * 9 - ddx / d * 2) * k + tvx * (1 - k);
          tvz = dv.vz + (ddx / d * 9 - ddz / d * 2) * k + tvz * (1 - k);
          if (p.y[i] < 16) tvy = 3.5 * k + tvy * (1 - k);
        }
      }
      p.vx[i] += (tvx - p.vx[i]) * math.min(1, dt * drag);
      p.vz[i] += (tvz - p.vz[i]) * math.min(1, dt * drag);
      p.vy[i] += (tvy - p.vy[i]) * math.min(1, dt * 2);
      p.x[i] += p.vx[i] * dt;
      p.y[i] += p.vy[i] * dt;
      p.z[i] += p.vz[i] * dt;
      p.phase[i] = ph + dt * (kind == PK.snow ? 1.5 : 4 + wind.speed * 0.3);
      p.ang[i] += p.angV[i] * dt;
      final gh = city.heightAt(p.x[i], p.z[i]);
      if (gh < -50) {
        // Off the board: fall over the edge.
        if (p.y[i] < -25) p.kill(i);
        continue;
      }
      if (p.y[i] <= gh + 0.03) {
        p.y[i] = gh + 0.03;
        p.state[i] = 2;
        p.life[i] = kind == PK.snow ? 2.5 : 40 + _r.nextDouble() * 20;
      }
    }
  }
}
