import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/lighting.dart';
import '../engine/renderer.dart';
import '../engine/scene.dart';
import 'city.dart';
import 'monuments.dart';
import 'props.dart';
import 'simulation.dart';

class _Build {
  final Lot lot;
  final List<SceneObject> objs;
  final List<double> target;
  double t = 0;
  _Build(this.lot, this.objs, this.target);
}

class _Drop {
  final SceneObject obj;
  final double baseY;
  _Drop(this.obj, this.baseY);
}

class _CamAnim {
  final double tx0, tz0, d0, p0, y0, tx1, tz1, d1, p1, y1;
  double t = 0;
  _CamAnim(
    this.tx0,
    this.tz0,
    this.d0,
    this.p0,
    this.y0,
    this.tx1,
    this.tz1,
    this.d1,
    this.p1,
    this.y1,
  );
}

/// Top-level simulation state shared by the renderer and the UI.
class World extends ChangeNotifier {
  final scene = Scene();
  final renderer = Renderer();
  final traffic = Traffic();
  final wind = Wind();
  final weather = Weather();
  late City city;

  double time = 0;
  int _lightVersion = 1;
  bool _lightDirty = true;

  // Settings.
  double _hour = 17.6;
  Season _season = Season.autumn;
  double trafficAmount = 1.75;
  double treeDensity = 1;
  bool tiltShift = true;
  bool moveBlocks = false;
  bool sound = false;
  bool music = false;

  Lot? selected;
  Block? moveFrom;
  final _builds = <_Build>[];
  final _drops = <_Drop>[];
  double _dropT = 1;
  _CamAnim? _camAnim;

  /// Incremented whenever something worth a sound effect happens.
  int buildEvents = 0;
  int gustEvents = 0;
  int devilEvents = 0;
  int swapEvents = 0;

  double fps = 60;

  World() {
    city = City(5, 5, 1234);
    _rebuild();
    final cam = renderer.cam;
    cam.dist = 330;
    cam.yaw = -0.22;
    cam.pitch = 0.83;
  }

  bool get building => _builds.isNotEmpty;

  double get hour => _hour;
  set hour(double v) {
    _hour = v;
    _lightDirty = true;
    notifyListeners();
  }

  Season get season => _season;
  set season(Season s) {
    _season = s;
    _lightDirty = true;
    // Clear fallen leaves / snow from the previous season.
    scene.particles.clear();
    notifyListeners();
  }

  Light get light => scene.light;

  void _rebuild() {
    city.treeDensity = treeDensity;
    selected = null;
    moveFrom = null;
    _builds.clear();
    city.build(scene);
    traffic.amount = trafficAmount;
    traffic.rehome(scene, city);
    _lightDirty = true;
  }

  void setTraffic(double v) {
    trafficAmount = v;
    traffic.amount = v;
    traffic.populate(scene, city);
    notifyListeners();
  }

  void setTreeDensity(double v) {
    treeDensity = v;
    _rebuild();
    notifyListeners();
  }

  void resize(int nx, int nz) {
    if (nx == city.nx && nz == city.nz) return;
    city.resize(nx, nz);
    scene.particles.clear();
    _rebuild();
    notifyListeners();
  }

  void switchTrees() {
    city.treeStyle =
        TreeStyle.values[(city.treeStyle.index + 1) % TreeStyle.values.length];
    _rebuild();
    notifyListeners();
  }

  void resetBlocks() {
    city.resetBlocks();
    _rebuild();
    swapEvents++;
    notifyListeners();
  }

  void resetHouses() {
    city.resetHouses();
    _rebuild();
    buildEvents++;
    notifyListeners();
  }

  void gust() {
    wind.gust = Wind.gustLen;
    gustEvents++;
    notifyListeners();
  }

  void leafDevil() {
    weather.startDevil(city, wind);
    devilEvents++;
    notifyListeners();
  }

  void toggleMoveBlocks() {
    moveBlocks = !moveBlocks;
    _setMoveFrom(null);
    if (moveBlocks) _select(null);
    notifyListeners();
  }

  void wholeMap() {
    final cam = renderer.cam;
    final span = math.max(city.width, city.depth);
    final d = span * 0.62 / math.tan(cam.fov / 2);
    _camAnim = _CamAnim(
      cam.tx,
      cam.tz,
      cam.dist,
      cam.pitch,
      cam.yaw,
      0,
      0,
      d,
      0.9,
      cam.yaw,
    );
  }

  // ---------------------------------------------------------------------
  // Interaction.

  void orbit(double dx, double dy) {
    final cam = renderer.cam;
    _camAnim = null;
    cam.yaw -= dx * 0.006;
    cam.pitch = (cam.pitch + dy * 0.004).clamp(0.25, 1.45);
  }

  void pan(double dx, double dy) {
    final cam = renderer.cam;
    _camAnim = null;
    final k = cam.dist / cam.focal;
    // Move along the ground plane.
    final fx = cam.fx, fz = cam.fz;
    final fl = math.sqrt(fx * fx + fz * fz);
    final lim = math.max(city.width, city.depth) * 0.6;
    cam.tx = (cam.tx - dx * k * cam.rx + dy * k * fx / fl * 1.3).clamp(
      -lim,
      lim,
    );
    cam.tz = (cam.tz - dx * k * cam.rz + dy * k * fz / fl * 1.3).clamp(
      -lim,
      lim,
    );
  }

  void zoom(double factor) {
    final cam = renderer.cam;
    _camAnim = null;
    cam.dist = (cam.dist * factor).clamp(40.0, 1400.0);
  }

  void tap(double x, double y) {
    if (moveBlocks) {
      final hit = renderer.cam.groundHit(x, y, 0.3);
      final b = hit == null ? null : city.blockAt(hit.$1, hit.$2);
      if (b == null) {
        _setMoveFrom(null);
      } else if (moveFrom == null) {
        _setMoveFrom(b);
      } else if (identical(moveFrom, b)) {
        _setMoveFrom(null);
      } else {
        _swap(moveFrom!, b);
      }
      notifyListeners();
      return;
    }
    final o = renderer.pick(x, y);
    final owner = o?.owner;
    _select(owner is Lot ? owner : null);
    notifyListeners();
  }

  void _select(Lot? l) {
    if (selected != null) {
      for (final o in selected!.objects) {
        o.highlight = 0;
      }
    }
    selected = l;
  }

  void deselect() {
    _select(null);
    notifyListeners();
  }

  List<SceneObject> _blockObjects(Block b) {
    final res = <SceneObject>[];
    for (final o in scene.objects) {
      if (o.x >= b.x0 &&
          o.x <= b.x0 + City.block &&
          o.z >= b.z0 &&
          o.z <= b.z0 + City.block) {
        if (traffic.cars.any((c) => identical(c.obj, o))) continue;
        if (traffic.people.any((p) => identical(p.obj, o))) continue;
        res.add(o);
      }
    }
    return res;
  }

  void _setMoveFrom(Block? b) {
    if (moveFrom != null) {
      for (final o in _blockObjects(moveFrom!)) {
        o.highlight = 0;
        o.y = _liftBase[o] ?? o.y;
      }
      _liftBase.clear();
    }
    moveFrom = b;
    scene.outline = b == null
        ? null
        : [b.x0, b.z0, b.x0 + City.block, b.z0 + City.block, 0.32];
    if (b != null) {
      for (final o in _blockObjects(b)) {
        _liftBase[o] = o.y;
        o.highlight = 0.28;
      }
    }
  }

  final _liftBase = <SceneObject, double>{};

  void _swap(Block a, Block b) {
    _setMoveFrom(null);
    final ai = a.i, aj = a.j, bi = b.i, bj = b.j;
    city.swap(a, b);
    _rebuild();
    swapEvents++;
    // Drop the two blocks back into place.
    _drops.clear();
    for (final nb in city.blocks) {
      if ((nb.i == ai && nb.j == aj) || (nb.i == bi && nb.j == bj)) {
        for (final o in _blockObjects(nb)) {
          _drops.add(_Drop(o, o.y));
        }
      }
    }
    _dropT = 0;
  }

  void setMonument(Lot l, Monument? m) {
    if (m == null) {
      l.block.content.monuments.remove(l.index);
    } else {
      l.block.content.monuments[l.index] = m;
    }
    city.spinners.removeWhere((s) => l.objects.contains(s.obj));
    for (final o in l.objects) {
      o.highlight = 0;
    }
    city.buildLot(l, scene);
    final target = <double>[];
    for (final o in l.objects) {
      target.add(o.sy);
      o.sy = 0.01;
      if (o.dynamicLight) o.visible = false;
    }
    _builds.removeWhere((b) => identical(b.lot, l));
    _builds.add(_Build(l, List.of(l.objects), target));
    weather.dust(scene.particles, l.cx, 0.5, l.cz, 40);
    city.updateShadows(scene);
    buildEvents++;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Frame update.

  void update(double dt) {
    dt = dt.clamp(0.0, 0.1);
    time += dt;

    if (_lightDirty) {
      _lightDirty = false;
      scene.light = Light(_hour, _season)..version = ++_lightVersion;
      city.updateShadows(scene);
    }

    wind.update(dt, time);
    traffic.update(dt, city, time);
    weather.update(dt, time, scene, city, wind);

    // Tree sway.
    final ws = wind.speed;
    final wl = ws > 0.01 ? 1 / ws : 0.0;
    final dirx = wind.vx * wl, dirz = wind.vz * wl;
    final dv = weather.devil;
    for (final t in city.trees) {
      final o = t.obj;
      final f = 1.2 + t.stiffness * 0.5;
      final osc = math.sin(time * f + t.phase) * 0.5 + 0.5;
      final amp = (0.0045 * ws + 0.0004 * ws * ws) * t.stiffness;
      var sx =
          dirx * amp * (0.55 + 0.45 * osc) +
          math.sin(time * 2.3 + t.phase * 3) * 0.004;
      var sz =
          dirz * amp * (0.55 + 0.45 * osc) +
          math.cos(time * 2.1 + t.phase * 2) * 0.004;
      if (dv != null) {
        final ddx = o.x - dv.x, ddz = o.z - dv.z;
        final d2 = ddx * ddx + ddz * ddz;
        if (d2 < 160) {
          final k = (1 - d2 / 160) * 0.12;
          sx += -ddz / 12 * k + math.sin(time * 9) * k * 0.5;
          sz += ddx / 12 * k;
        }
      }
      o.shx = sx;
      o.shz = sz;
    }

    // Spinners.
    for (final s in city.spinners) {
      final rate = s.windDriven ? 0.08 + wind.speed * 0.09 : s.rate;
      s.obj.spin += rate * dt;
    }

    // Construction animation.
    for (final b in List.of(_builds)) {
      b.t += dt / 1.8;
      final t = math.min(1.0, b.t);
      final e = _easeOutBack(t);
      for (var k = 0; k < b.objs.length; k++) {
        final o = b.objs[k];
        if (o.dynamicLight) continue;
        o.sy = math.max(0.01, b.target[k] * e);
      }
      if (time % 0.25 < dt && t < 0.8) {
        weather.dust(scene.particles, b.lot.cx, 0.4, b.lot.cz, 6);
      }
      if (b.t >= 1) {
        for (var k = 0; k < b.objs.length; k++) {
          b.objs[k].sy = b.target[k];
          b.objs[k].visible = true;
        }
        _builds.remove(b);
        city.updateShadows(scene);
        city.refreshHeights(scene);
        notifyListeners();
      }
    }

    // Block swap drop animation.
    if (_dropT < 1) {
      _dropT = math.min(1, _dropT + dt / 0.7);
      final e = 1 - _easeOutBounce(_dropT);
      for (final d in _drops) {
        d.obj.y = d.baseY + e * 14;
      }
      if (_dropT >= 1) _drops.clear();
    }

    // Lifted block in move mode hovers.
    if (moveFrom != null) {
      final h = 2.5 + math.sin(time * 3) * 0.6;
      _liftBase.forEach((o, y) => o.y = y + h);
    }

    // Selection pulse.
    if (selected != null) {
      final p = 0.18 + 0.1 * math.sin(time * 4);
      for (final o in selected!.objects) {
        o.highlight = p;
      }
    }

    // Camera animation.
    final a = _camAnim;
    if (a != null) {
      a.t = math.min(1, a.t + dt / 1.2);
      final e = _easeInOut(a.t);
      final cam = renderer.cam;
      cam.tx = a.tx0 + (a.tx1 - a.tx0) * e;
      cam.tz = a.tz0 + (a.tz1 - a.tz0) * e;
      cam.dist = a.d0 + (a.d1 - a.d0) * e;
      cam.pitch = a.p0 + (a.p1 - a.p0) * e;
      cam.yaw = a.y0 + (a.y1 - a.y0) * e;
      if (a.t >= 1) _camAnim = null;
    }
  }

  static double _easeOutBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    final u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
  }

  static double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  static double _easeOutBounce(double t) {
    const n1 = 7.5625, d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) {
      t -= 1.5 / d1;
      return n1 * t * t + 0.75;
    }
    if (t < 2.5 / d1) {
      t -= 2.25 / d1;
      return n1 * t * t + 0.9375;
    }
    t -= 2.625 / d1;
    return n1 * t * t + 0.984375;
  }
}
