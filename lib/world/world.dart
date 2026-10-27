import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/lighting.dart';
import '../engine/renderer.dart';
import '../engine/scene.dart';
import 'city.dart';
import 'monuments.dart';
import 'props.dart';
import 'simulation.dart';

/// One object being built, grown in or demolished (#6).
class _Job {
  final SceneObject obj;
  final double start, dur;
  final _JobKind kind;
  final double sx, sy, sz;
  final Block? block;
  bool started = false;
  _Job(this.obj, this.start, this.dur, this.kind, this.block)
    : sx = obj.sx,
      sy = obj.sy,
      sz = obj.sz;
}

enum _JobKind { parts, grow, demolish }

/// What a click on the town does.
enum ToolMode { view, move, build }

/// Undo entry: the layout order plus a copy of every block's content.
class _Snapshot {
  final List<BlockContent> refs;
  final List<BlockContent> copies;
  _Snapshot(List<BlockContent> layout)
    : refs = List.of(layout),
      copies = [for (final c in layout) c.copy()];
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
  double _lightAppliedAt = -1;

  // Settings.
  double _hour = 17.6;
  Season _season = Season.autumn;
  double trafficAmount = 1.75;
  double treeDensity = 1;
  bool tiltShift = true;

  /// Supersampled anti-aliasing; on by default only where pixels are big
  /// enough for jaggies to show (#5).
  bool smoothEdges = true;
  double supersampleFactor = 1.5;

  /// While true, [reportFps] may switch [smoothEdges] off on slow machines.
  bool autoSmooth = true;
  int _slowSamples = 0;

  /// Called twice a second with the measured frame rate. Supersampling is
  /// dropped after 2 s below 45 fps (outside construction), so slow
  /// machines keep their frame rate; the button turns it back on (#5).
  void reportFps(double v) {
    fps = v;
    if (!smoothEdges || !autoSmooth || time < 3) return;
    _slowSamples = v < 45 ? _slowSamples + 1 : 0;
    if (_slowSamples >= 4) {
      smoothEdges = false;
      autoSmooth = false;
      notifyListeners();
    }
  }

  ToolMode mode = ToolMode.view;
  bool get moveBlocks => mode == ToolMode.move;
  bool get buildMode => mode == ToolMode.build;

  /// Tile picked in build mode (#7).
  Block? selectedBlock;
  Block? _hoverBlock;
  final _undo = <_Snapshot>[];
  static const _undoLimit = 50;
  bool get canUndo => _undo.isNotEmpty;
  bool sound = false;
  bool music = false;

  Lot? selected;
  Block? moveFrom;
  final _jobs = <_Job>[];
  double _shadowsAt = 0;
  bool _intro = false;
  _CamAnim? _camAnim;

  /// Incremented whenever something worth a sound effect happens.
  int buildEvents = 0;
  int gustEvents = 0;
  int devilEvents = 0;
  int swapEvents = 0;

  double fps = 60;
  double simMs = 0;

  World() {
    city = City(5, 5, 1234);
    _rebuild();
    _queueAll(intro: true);
    final cam = renderer.cam;
    cam.dist = 330;
    cam.yaw = -0.22;
    cam.pitch = 0.83;
  }

  bool get building => _jobs.isNotEmpty;

  /// Blocks still under construction (footer "building N blocks…").
  int get buildingBlocks => {
    for (final j in _jobs)
      if (j.kind != _JobKind.demolish && j.block != null) j.block,
  }.length;

  bool isBuilding(Lot l) => _jobs.any(
    (j) => j.kind != _JobKind.demolish && l.objects.contains(j.obj),
  );

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
    selectedBlock = null;
    _hoverBlock = null;
    scene.outline = null;
    _finishJobs();
    city.build(scene);
    traffic.amount = trafficAmount;
    traffic.rehome(scene, city);
    _lightDirty = true;
  }

  /// Replaces the whole town (saved state, share link, New town; #9).
  void loadCity(
    City c, {
    double? hour,
    Season? season,
    double? windBase,
    double? windFrom,
    double? traffic,
    double? trees,
    double? leaves,
    double? leafSize,
    bool? tiltShift,
  }) {
    city = c;
    if (hour != null) _hour = hour;
    if (season != null) _season = season;
    if (windBase != null) wind.base = windBase;
    if (windFrom != null) wind.fromDeg = windFrom;
    if (traffic != null) trafficAmount = traffic;
    if (trees != null) treeDensity = trees;
    if (leaves != null) weather.leaves = leaves;
    if (leafSize != null) weather.leafSize = leafSize;
    if (tiltShift != null) this.tiltShift = tiltShift;
    _undo.clear();
    scene.particles.clear();
    _rebuild();
    _queueAll(intro: true);
    _lightDirty = true;
    notifyListeners();
  }

  /// A freshly generated 5×5 town; settings are kept.
  void newTown() {
    final c = City(5, 5, math.Random().nextInt(1 << 30))
      ..treeStyle = city.treeStyle;
    loadCity(c);
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
    _queueTrees();
    notifyListeners();
  }

  void resize(int nx, int nz) {
    if (nx == city.nx && nz == city.nz) return;
    final ox = city.nx, oz = city.nz;
    _undo.clear(); // snapshots cover one map size only
    city.resize(nx, nz);
    scene.particles.clear();
    _rebuild();
    // Blocks coming back from a shrink are built up again (#6).
    var k = 0;
    for (final b in city.blocks) {
      if ((b.i >= ox || b.j >= oz) && b.objects.isNotEmpty) {
        _queueBlock(b, 0.15 * k++);
      }
    }
    notifyListeners();
  }

  void switchTrees() {
    city.treeStyle =
        TreeStyle.values[(city.treeStyle.index + 1) % TreeStyle.values.length];
    _rebuild();
    _queueTrees();
    notifyListeners();
  }

  void resetBlocks() {
    _pushUndo();
    city.resetBlocks();
    _rebuild();
    _queueAll();
    swapEvents++;
    notifyListeners();
  }

  void resetHouses() {
    final touched = [
      for (final b in city.blocks)
        if (b.content.lots.isNotEmpty) b,
    ];
    if (touched.isNotEmpty) _pushUndo();
    city.resetHouses();
    _rebuildAnimated(touched);
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

  void toggleMoveBlocks() =>
      setMode(moveBlocks ? ToolMode.view : ToolMode.move);

  void toggleBuild() => setMode(buildMode ? ToolMode.view : ToolMode.build);

  void setMode(ToolMode m) {
    mode = m;
    _setMoveFrom(null);
    selectedBlock = null;
    _hoverBlock = null;
    _select(null);
    _updateOutline();
    notifyListeners();
  }

  /// Pointer moved over the town (outlines the tile under it in tool modes).
  void hover(double x, double y) {
    if (mode == ToolMode.view) return;
    final hit = renderer.cam.groundHit(x, y, 0.3);
    final b = hit == null ? null : city.blockAt(hit.$1, hit.$2);
    if (!identical(b, _hoverBlock)) {
      _hoverBlock = b;
      _updateOutline();
    }
  }

  void _updateOutline() {
    final b = moveFrom ?? selectedBlock ?? _hoverBlock;
    scene.outline = b == null
        ? null
        : [b.x0, b.z0, b.x0 + City.block, b.z0 + City.block, 0.32];
  }

  // ---------------------------------------------------------------------
  // Editing tools (#7, #8) with undo.

  void _pushUndo() {
    _undo.add(_Snapshot(city.layout));
    if (_undo.length > _undoLimit) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    if (s.refs.length != city.layout.length) return;
    final changed = <Block>[];
    for (var k = 0; k < s.refs.length; k++) {
      final cur = city.layout[k];
      if (!identical(cur, s.refs[k]) || !cur.sameAs(s.copies[k])) {
        changed.add(city.blocks[k]);
      }
    }
    city.layout = List.of(s.refs);
    for (var k = 0; k < s.refs.length; k++) {
      s.refs[k].assign(s.copies[k]);
    }
    _select(null);
    _rebuildAnimated(changed);
    _reselectBlock();
    notifyListeners();
  }

  void _reselectBlock() {
    final b = selectedBlock;
    if (b != null) selectedBlock = city.blockAtCell(b.i, b.j);
    _updateOutline();
  }

  /// Turns a tile into another kind of block (#7).
  void setTileKind(Block b, BlockKind kind) {
    _pushUndo();
    final c = b.content;
    c.kind = kind;
    c.seed = math.Random().nextInt(1 << 30);
    c.lots.clear();
    _rebuildAnimated([b]);
    _reselectBlock();
    buildEvents++;
    notifyListeners();
  }

  /// Same kind of block, new random layout and colours (#7).
  void tileVariant(Block b) => setTileKind(b, b.content.kind);

  void clearTile(Block b) => setTileKind(b, BlockKind.empty);

  /// Applies [change] to a lot's edits and rebuilds just that lot (#8).
  void editLot(Lot l, void Function(LotOverride e) change) {
    _pushUndo();
    final c = l.block.content;
    change(c.edit(l.index));
    if (c.lots[l.index]!.isDefault) c.lots.remove(l.index);
    _rebuildLot(l);
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
    if (_intro) {
      // A click skips the opening construction.
      _finishJobs();
      city.updateShadows(scene);
      city.refreshHeights(scene);
      notifyListeners();
      return;
    }
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
    if (buildMode) {
      if (owner is Lot) {
        selectedBlock = null;
        _select(owner);
      } else {
        // Ground or decoration: pick the tile (empty lots included).
        final hit = renderer.cam.groundHit(x, y, 0.3);
        final b = hit == null ? null : city.blockAt(hit.$1, hit.$2);
        final lot = b == null ? null : _lotAt(b, hit!.$1, hit.$2);
        _select(lot != null && lot.demolished ? lot : null);
        selectedBlock = lot != null && lot.demolished ? null : b;
      }
      _updateOutline();
      notifyListeners();
      return;
    }
    _select(owner is Lot ? owner : null);
    notifyListeners();
  }

  /// The lot of [b] whose footprint contains (x, z), if any.
  Lot? _lotAt(Block b, double x, double z) {
    for (final l in b.lots) {
      final c = math.cos(l.baseRot).abs(), s = math.sin(l.baseRot).abs();
      final hx = (c * l.w + s * l.d) / 2, hz = (s * l.w + c * l.d) / 2;
      if ((x - l.cx).abs() < hx && (z - l.cz).abs() < hz) return l;
    }
    return null;
  }

  /// Selects a lot as if it was clicked (QA hook, panels).
  void selectLot(Lot l) {
    selectedBlock = null;
    _select(l);
    _updateOutline();
    notifyListeners();
  }

  void selectTile(Block b) {
    _select(null);
    selectedBlock = b;
    _updateOutline();
    notifyListeners();
  }

  /// Press-and-hold on touch screens: Build mode with that tile picked.
  void longPress(double x, double y) {
    final hit = renderer.cam.groundHit(x, y, 0.3);
    final b = hit == null ? null : city.blockAt(hit.$1, hit.$2);
    if (b == null) return;
    if (!buildMode) setMode(ToolMode.build);
    selectTile(b);
  }

  void deselectTile() {
    selectedBlock = null;
    _updateOutline();
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

  List<SceneObject> _blockObjects(Block b) => b.objects;

  void _setMoveFrom(Block? b) {
    if (moveFrom != null) {
      for (final o in _blockObjects(moveFrom!)) {
        o.highlight = 0;
        o.y = _liftBase[o] ?? o.y;
      }
      _liftBase.clear();
    }
    moveFrom = b;
    _updateOutline();
    if (b != null) {
      for (final o in _blockObjects(b)) {
        _liftBase[o] = o.y;
        o.highlight = 0.28;
      }
    }
  }

  final _liftBase = <SceneObject, double>{};

  /// Swaps two blocks (Move blocks).
  void swapBlocks(Block a, Block b) => _swap(a, b);

  void _swap(Block a, Block b) {
    _setMoveFrom(null);
    _select(null);
    _pushUndo();
    city.swap(a, b);
    // Only the two blocks are rebuilt (#4), and they are built up again (#6).
    _rebuildAnimated([a, b]);
    swapEvents++;
  }

  /// Rebuilds [blocks]: old buildings shrink away, new ones rise (#6).
  void _rebuildAnimated(List<Block> blocks) {
    if (blocks.isEmpty) return;
    final old = [for (final b in blocks) ...b.objects];
    _jobs.removeWhere((j) => old.contains(j.obj));
    city.rebuildBlocks(blocks, scene);
    _demolish(old);
    var k = 0;
    for (final b in blocks) {
      _queueBlock(city.blockAtCell(b.i, b.j), 0.35 + 0.25 * k++);
    }
  }

  /// Replaces a house with a monument, or brings the house back (null).
  void setMonument(Lot l, Monument? m) => editLot(l, (e) {
    e.monument = m;
    if (m == null) {
      // "Original": the generated house, no other edits either.
      e
        ..style = null
        ..floors = null
        ..facade = null
        ..roof = null
        ..roofKind = null
        ..rotSteps = 0
        ..seed = null
        ..demolished = false;
    } else {
      e.demolished = false;
    }
  });

  void _rebuildLot(Lot l) {
    for (final o in l.objects) {
      o.highlight = 0;
    }
    final old = List.of(l.objects);
    _jobs.removeWhere((j) => old.contains(j.obj));
    city.buildLot(l, scene);
    _demolish(old);
    _queueLot(l, 0.35);
    city.updateShadows(scene);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Construction queue (#6).

  void _queueAll({bool intro = false}) {
    // Blocks rise one after another, starting from the middle of town.
    final order = List.of(city.blocks)
      ..sort((a, b) {
        double d(Block x) => x.cx * x.cx + x.cz * x.cz;
        return d(a).compareTo(d(b));
      });
    var k = 0;
    for (final b in order) {
      if (b.objects.isEmpty) continue;
      _queueBlock(b, (intro ? 0.4 : 0.1) + 0.14 * k++);
    }
    _intro = intro;
  }

  void _queueBlock(Block b, double delay) {
    var k = 0;
    final lotObjs = <SceneObject>{};
    for (final l in b.lots) {
      lotObjs.addAll(l.objects);
      _queueLot(l, delay + 0.12 * k++);
    }
    final r = math.Random(b.content.seed);
    for (final o in b.objects) {
      if (lotObjs.contains(o)) continue;
      _add(o, delay + r.nextDouble() * 0.9, 0.55, _JobKind.grow, b);
    }
  }

  void _queueLot(Lot l, double delay) {
    for (final o in l.objects) {
      if (o.dynamicLight) {
        // Sails and wheels appear once the structure stands.
        _add(o, delay + 1.4, 0.5, _JobKind.grow, l.block);
      } else {
        final parts = o.mesh.partCount;
        final dur = (0.5 + 0.09 * parts).clamp(0.8, 2.6);
        _add(o, delay, dur, _JobKind.parts, l.block);
      }
    }
  }

  void _queueTrees() {
    final r = math.Random(7);
    for (final t in city.trees) {
      _add(t.obj, r.nextDouble() * 1.2, 0.5, _JobKind.grow, null);
    }
  }

  void _add(SceneObject o, double delay, double dur, _JobKind kind, Block? b) {
    final j = _Job(o, time + delay, dur, kind, b);
    if (kind == _JobKind.parts) o.build = 0;
    if (kind == _JobKind.grow) o.visible = false;
    _jobs.add(j);
  }

  void _demolish(List<SceneObject> old) {
    for (final o in old) {
      o.highlight = 0;
      if (!o.visible) continue;
      scene.objects.add(o);
      _jobs.add(_Job(o, time, 0.35, _JobKind.demolish, null));
    }
  }

  /// Completes all construction immediately (tests, skipping the intro).
  void finishConstruction() {
    _finishJobs();
    city.updateShadows(scene);
    city.refreshHeights(scene);
  }

  /// Completes every pending job at once (skip the intro, full rebuilds).
  void _finishJobs() {
    for (final j in _jobs) {
      _applyJob(j, 1);
      if (j.kind == _JobKind.demolish) scene.objects.remove(j.obj);
    }
    _jobs.clear();
    _intro = false;
  }

  void _applyJob(_Job j, double t) {
    final o = j.obj;
    switch (j.kind) {
      case _JobKind.parts:
        o.build = t;
      case _JobKind.grow:
        final e = t >= 1 ? 1.0 : _easeOutBack(t);
        o.visible = t > 0;
        o.sx = j.sx * e;
        o.sy = j.sy * e;
        o.sz = j.sz * e;
      case _JobKind.demolish:
        final e = 1 - t * t;
        o.sy = math.max(0.001, j.sy * e);
        o.sx = j.sx * (0.85 + 0.15 * e);
        o.sz = j.sz * (0.85 + 0.15 * e);
    }
  }

  void _runJobs() {
    if (_jobs.isEmpty) return;
    var finished = false;
    for (var k = _jobs.length - 1; k >= 0; k--) {
      final j = _jobs[k];
      final t = (time - j.start) / j.dur;
      if (t <= 0) {
        _applyJob(j, 0);
        continue;
      }
      if (!j.started) {
        j.started = true;
        if (j.kind == _JobKind.parts) {
          final o = j.obj;
          weather.dust(scene.particles, o.x, o.y + 0.3, o.z, 14);
          buildEvents++;
        }
      }
      if (t >= 1) {
        _applyJob(j, 1);
        if (j.kind == _JobKind.demolish) scene.objects.remove(j.obj);
        _jobs.removeAt(k);
        finished = true;
      } else {
        _applyJob(j, t);
      }
    }
    if (_jobs.isEmpty) {
      _intro = false;
      city.updateShadows(scene);
      city.refreshHeights(scene);
      notifyListeners();
    } else if (finished && time - _shadowsAt > 0.4) {
      _shadowsAt = time;
      city.updateShadows(scene);
    }
  }

  // ---------------------------------------------------------------------
  // Frame update.

  void update(double dt) {
    dt = dt.clamp(0.0, 0.1);
    time += dt;

    // While a slider is dragged, relight at most ~10 times a second; the
    // last value always lands (#4).
    if (_lightDirty && time - _lightAppliedAt >= 0.1) {
      _lightDirty = false;
      _lightAppliedAt = time;
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

    // Construction queue.
    _runJobs();

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
}
