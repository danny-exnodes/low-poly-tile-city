import 'dart:math' as math;
import 'dart:typed_data';

import '../engine/lighting.dart';
import '../engine/mesh.dart';
import '../engine/scene.dart';
import 'buildings.dart';
import 'monuments.dart';
import 'props.dart';

enum BlockKind {
  empty,
  residential,
  townhouses,
  downtown,
  apartments,
  park,
  plaza,
  fair,
  farm,
  supermarket,
  hospital,
  sports,
  church,
}

/// User edits of one lot (#8). Unset fields fall back to what the block's
/// seed generates.
class LotOverride {
  HouseStyle? style;
  int? floors;
  int? facade;
  int? roof;
  RoofKind? roofKind;
  int rotSteps = 0;
  int? seed;
  bool demolished = false;
  Monument? monument;

  LotOverride copy() => LotOverride()
    ..style = style
    ..floors = floors
    ..facade = facade
    ..roof = roof
    ..roofKind = roofKind
    ..rotSteps = rotSteps
    ..seed = seed
    ..demolished = demolished
    ..monument = monument;

  bool get isDefault =>
      style == null &&
      floors == null &&
      facade == null &&
      roof == null &&
      roofKind == null &&
      rotSteps == 0 &&
      seed == null &&
      !demolished &&
      monument == null;

  @override
  bool operator ==(Object other) =>
      other is LotOverride &&
      other.style == style &&
      other.floors == floors &&
      other.facade == facade &&
      other.roof == roof &&
      other.roofKind == roofKind &&
      other.rotSteps == rotSteps &&
      other.seed == seed &&
      other.demolished == demolished &&
      other.monument == monument;

  @override
  int get hashCode => Object.hash(
    style,
    floors,
    facade,
    roof,
    roofKind,
    rotSteps,
    seed,
    demolished,
    monument,
  );
}

/// What lives on a block. Swapped around by "Move blocks".
class BlockContent {
  BlockKind kind;
  int seed;

  /// Per-lot edits and monuments, by lot index (#8).
  final Map<int, LotOverride> lots = {};
  BlockContent(this.kind, this.seed);

  BlockContent copy() =>
      BlockContent(kind, seed)
        ..lots.addAll({for (final e in lots.entries) e.key: e.value.copy()});

  /// Copies [other]'s state into this object (undo restores in place).
  void assign(BlockContent other) {
    kind = other.kind;
    seed = other.seed;
    lots
      ..clear()
      ..addAll({for (final e in other.lots.entries) e.key: e.value.copy()});
  }

  bool sameAs(BlockContent o) {
    if (o.kind != kind || o.seed != seed || o.lots.length != lots.length) {
      return false;
    }
    for (final e in lots.entries) {
      if (o.lots[e.key] != e.value) return false;
    }
    return true;
  }

  LotOverride edit(int lot) => lots.putIfAbsent(lot, LotOverride.new);
}

class Lot {
  final Block block;
  final int index;
  final double cx, cz, w, d;

  /// Generated orientation, style and seed; see the getters for the values
  /// after user edits.
  final double baseRot;
  final HouseStyle baseStyle;
  final int baseSeed;
  final objects = <SceneObject>[];
  Lot(
    this.block,
    this.index,
    this.cx,
    this.cz,
    this.w,
    this.d,
    this.baseRot,
    this.baseStyle,
    this.baseSeed,
  );

  LotOverride? get edits => block.content.lots[index];
  Monument? get monument => edits?.monument;
  HouseStyle get style => edits?.style ?? baseStyle;
  int get seed => edits?.seed ?? baseSeed;
  double get rot => baseRot + (edits?.rotSteps ?? 0) * math.pi / 2;
  bool get demolished => edits?.demolished ?? false;

  /// Square lots can turn by quarter turns; others only by half turns.
  bool get square => (w - d).abs() < 0.5;

  String get name =>
      demolished ? 'Empty lot' : (monument?.label ?? style.label);
}

class Block {
  final int i, j;
  BlockContent content;
  final double x0, z0;
  final lots = <Lot>[];

  /// Everything built for this block, so it can be rebuilt alone (#4).
  final objects = <SceneObject>[];
  final trees = <TreeInfo>[];
  final spinners = <Spinner>[];
  final lamps = <double>[];
  SceneObject? ground;
  Block(this.i, this.j, this.content, this.x0, this.z0);
  double get cx => x0 + City.block / 2;
  double get cz => z0 + City.block / 2;
}

class TreeInfo {
  final SceneObject obj;
  final double crownY, crownR;
  final bool deciduous;
  final double phase, stiffness;
  TreeInfo(
    this.obj,
    this.crownY,
    this.crownR,
    this.deciduous,
    this.phase,
    this.stiffness,
  );
}

/// A spinning decoration (ferris wheel, windmill sails, carousel).
class Spinner {
  final SceneObject obj;
  final double rate;
  final bool windDriven;
  Spinner(this.obj, this.rate, {this.windDriven = false});
}

/// Procedural city layout and static geometry.
class City {
  static const block = 40.0;
  static const road = 10.0;
  static const pitch = block + road;
  static const walk = 3.0;

  int nx, nz;
  final int seed;
  TreeStyle treeStyle = TreeStyle.mixed;
  double treeDensity = 1;

  late List<BlockContent> layout;
  late List<BlockContent> original;

  final blocks = <Block>[];
  final trees = <TreeInfo>[];
  final spinners = <Spinner>[];

  /// Blocks cut off by shrinking the map, restored when it grows back (#3).
  /// Value: (current content, original content).
  final _stash = <(int, int), (BlockContent, BlockContent)>{};

  /// Block currently being built; objects created meanwhile belong to it.
  Block? _cur;

  // Leaf landing height map (1 m cells).
  late Float32List heights;
  late int hw, hd;

  int _nextKey = 1;

  /// Kind and seed every block content started with (Reset blocks, #7).
  final _origin = Expando<(BlockKind, int)>();

  City(this.nx, this.nz, this.seed) {
    layout = _generateLayout(nx, nz, seed);
    original = List.of(layout);
    for (final c in layout) {
      _origin[c] = (c.kind, c.seed);
    }
  }

  double get width => nx * pitch + road;
  double get depth => nz * pitch + road;
  double nodeX(int i) => -width / 2 + road / 2 + i * pitch;
  double nodeZ(int j) => -depth / 2 + road / 2 + j * pitch;
  double blockX(int i) => -width / 2 + road + i * pitch;
  double blockZ(int j) => -depth / 2 + road + j * pitch;

  int get houseCount => blocks.fold(0, (s, b) => s + b.lots.length);

  static List<BlockContent> _generateLayout(int nx, int nz, int seed) {
    final r = math.Random(seed);
    final n = nx * nz;
    final specials = <BlockKind>[
      BlockKind.plaza,
      BlockKind.park,
      BlockKind.fair,
      BlockKind.supermarket,
      BlockKind.hospital,
      BlockKind.farm,
      BlockKind.sports,
      BlockKind.church,
      BlockKind.park,
    ];
    final kinds = List<BlockKind?>.filled(n, null);
    // Plaza in the middle.
    kinds[(nz ~/ 2) * nx + nx ~/ 2] = BlockKind.plaza;
    final budget = math.max(1, (n * 0.36).round());
    var placed = 1;
    final free = [
      for (var k = 0; k < n; k++)
        if (kinds[k] == null) k,
    ]..shuffle(r);
    for (final kind in specials.skip(1)) {
      if (placed >= budget || free.isEmpty) break;
      kinds[free.removeLast()] = kind;
      placed++;
    }
    const common = [
      BlockKind.townhouses,
      BlockKind.townhouses,
      BlockKind.townhouses,
      BlockKind.residential,
      BlockKind.residential,
      BlockKind.downtown,
      BlockKind.apartments,
    ];
    for (var k = 0; k < n; k++) {
      kinds[k] ??= common[r.nextInt(common.length)];
    }
    return [
      for (var k = 0; k < n; k++) BlockContent(kinds[k]!, r.nextInt(1 << 30)),
    ];
  }

  /// Changes the map size. Existing blocks stay put; new cells are empty
  /// land, or whatever was there before the map was shrunk (#3).
  void resize(int newNx, int newNz) {
    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        if (i >= newNx || j >= newNz) {
          _stash[(i, j)] = (layout[j * nx + i], original[j * nx + i]);
        }
      }
    }
    final keep = <BlockContent>[];
    final keepOrig = <BlockContent>[];
    for (var j = 0; j < newNz; j++) {
      for (var i = 0; i < newNx; i++) {
        if (i < nx && j < nz) {
          keep.add(layout[j * nx + i]);
          keepOrig.add(original[j * nx + i]);
        } else if (_stash.remove((i, j)) case (final cur, final orig)) {
          keep.add(cur);
          keepOrig.add(orig);
        } else {
          final empty = BlockContent(BlockKind.empty, seed ^ (i * 7919 + j));
          _origin[empty] = (empty.kind, empty.seed);
          keep.add(empty);
          keepOrig.add(empty);
        }
      }
    }
    nx = newNx;
    nz = newNz;
    layout = keep;
    original = keepOrig;
  }

  /// Puts every block back where it started, as the kind it started as.
  /// Edits stay with blocks that kept their kind (#7).
  void resetBlocks() {
    layout = List.of(original);
    for (final c in layout) {
      final o = _origin[c];
      if (o == null) continue;
      if (c.kind != o.$1 || c.seed != o.$2) {
        c.kind = o.$1;
        c.seed = o.$2;
        c.lots.clear();
      }
    }
  }

  /// Drops every building edit and monument (#8).
  void resetHouses() {
    for (final c in layout) {
      c.lots.clear();
    }
  }

  void swap(Block a, Block b) {
    final ia = a.j * nx + a.i, ib = b.j * nx + b.i;
    final t = layout[ia];
    layout[ia] = layout[ib];
    layout[ib] = t;
  }

  // ---------------------------------------------------------------------
  // Building the scene.

  void build(Scene scene) {
    scene.objects.clear();
    scene.movers.clear();
    blocks.clear();
    _nextKey = 1;
    _treeMeshes.clear();

    final g = MeshBuilder();
    _buildBoard(g);
    _board = SceneObject(g.build(), key: 0);

    for (var j = 0; j < nz; j++) {
      for (var i = 0; i < nx; i++) {
        final b = Block(i, j, layout[j * nx + i], blockX(i), blockZ(j));
        blocks.add(b);
        _buildWholeBlock(b, scene);
      }
    }
    scene.boardHalfW = width / 2;
    scene.boardHalfD = depth / 2;
    _finish(scene);
  }

  SceneObject? _board;

  void _buildWholeBlock(Block b, Scene scene) {
    _cur = b;
    final g = MeshBuilder();
    _buildBlock(b, g, scene);
    _buildStreetFurniture(b, scene);
    b.ground = SceneObject(g.build(), key: 0);
    _cur = null;
  }

  /// Rebuilds only the given blocks from the current layout (#4).
  void rebuildBlocks(Iterable<Block> which, Scene scene) {
    final gone = <SceneObject>{};
    for (final old in which) {
      gone.addAll(old.objects);
      final k = blocks.indexOf(old);
      if (k < 0) continue;
      final b = Block(old.i, old.j, layout[old.j * nx + old.i], old.x0, old.z0);
      blocks[k] = b;
      _buildWholeBlock(b, scene);
    }
    scene.objects.removeWhere(gone.contains);
    _finish(scene);
  }

  Block blockAtCell(int i, int j) => blocks[j * nx + i];

  /// Refreshes aggregated lists, ground, height map and shadows.
  void _finish(Scene scene) {
    trees
      ..clear()
      ..addAll(blocks.expand((b) => b.trees));
    spinners
      ..clear()
      ..addAll(blocks.expand((b) => b.spinners));
    scene.lamps = Float32List.fromList([for (final b in blocks) ...b.lamps]);
    scene.groundObjects
      ..clear()
      ..add(_board!)
      ..addAll(blocks.map((b) => b.ground!));
    scene.groundVersion++;
    _buildHeights(scene);
    updateShadows(scene);
  }

  SceneObject _add(
    Scene scene,
    Mesh m,
    double x,
    double y,
    double z, {
    double rot = 0,
    double tint = 0.5,
    Object? owner,
    bool shadow = true,
    Block? block,
  }) {
    final o = SceneObject(
      m,
      x: x,
      y: y,
      z: z,
      rot: rot,
      tint: tint,
      key: _nextKey * 977,
      owner: owner,
      castShadow: shadow,
    );
    _nextKey++;
    scene.objects.add(o);
    (block ?? _cur)?.objects.add(o);
    return o;
  }

  void _buildBoard(MeshBuilder g) {
    final w = width / 2, d = depth / 2;
    g.mat = Mat.plain;
    // Board slab with asphalt top.
    g.box(
      -w,
      -3,
      -d,
      w,
      0,
      d,
      Pal.asphalt,
      side: Pal.boardSide,
      top: Pal.asphalt,
    );
    // Lane markings.
    for (var j = 0; j <= nz; j++) {
      for (var i = 0; i < nx; i++) {
        final z = nodeZ(j);
        final a = nodeX(i) + road / 2 + 1, b = nodeX(i + 1) - road / 2 - 1;
        for (var x = a + 4; x < b - 4; x += 5) {
          g.flat(x, z - 0.12, x + 2.4, z + 0.12, 0.02, Pal.marking);
        }
      }
    }
    for (var i = 0; i <= nx; i++) {
      for (var j = 0; j < nz; j++) {
        final x = nodeX(i);
        final a = nodeZ(j) + road / 2 + 1, b = nodeZ(j + 1) - road / 2 - 1;
        for (var z = a + 4; z < b - 4; z += 5) {
          g.flat(x - 0.12, z, x + 0.12, z + 2.4, 0.02, Pal.marking);
        }
      }
    }
    // Zebra crossings around every intersection.
    for (var j = 0; j <= nz; j++) {
      for (var i = 0; i <= nx; i++) {
        final x = nodeX(i), z = nodeZ(j);
        const h = road / 2;
        if (i < nx) _zebra(g, x + h + 0.6, z, true);
        if (i > 0) _zebra(g, x - h - 3.0, z, true);
        if (j < nz) _zebra(g, x, z + h + 0.6, false);
        if (j > 0) _zebra(g, x, z - h - 3.0, false);
      }
    }
  }

  void _zebra(MeshBuilder g, double a, double c, bool alongX) {
    for (var k = -4; k <= 3; k++) {
      final o = c + k * 1.1 + 0.25;
      if (alongX) {
        g.flat(a, o, a + 2.4, o + 0.55, 0.02, Pal.marking);
      } else {
        g.flat(o, a, o + 0.55, a + 2.4, 0.02, Pal.marking);
      }
    }
  }

  /// Faceted grass patch with per-tile brightness jitter.
  void _grass(
    MeshBuilder g,
    double x0,
    double z0,
    double x1,
    double z1,
    double y,
    math.Random r, {
    double tile = 4,
  }) {
    g.mat = Mat.grass;
    final nx = math.max(1, ((x1 - x0) / tile).round());
    final nz = math.max(1, ((z1 - z0) / tile).round());
    final sx = (x1 - x0) / nx, sz = (z1 - z0) / nz;
    g.part();
    for (var a = 0; a < nx; a++) {
      for (var b = 0; b < nz; b++) {
        final ax = x0 + a * sx, az = z0 + b * sz;
        g.tri(
          V3(ax, y, az),
          V3(ax + sx, y, az),
          V3(ax + sx, y, az + sz),
          rgb8(r.nextInt(256)),
          out: V3.up,
        );
        g.tri(
          V3(ax, y, az),
          V3(ax + sx, y, az + sz),
          V3(ax, y, az + sz),
          rgb8(r.nextInt(256)),
          out: V3.up,
        );
      }
    }
    g.endPart();
    g.mat = Mat.plain;
  }

  void _paved(
    MeshBuilder g,
    double x0,
    double z0,
    double x1,
    double z1,
    double y,
    int c,
  ) {
    g.mat = Mat.paved;
    g.flat(x0, z0, x1, z1, y, c);
    g.mat = Mat.plain;
  }

  void _buildBlock(Block b, MeshBuilder g, Scene scene) {
    final r = math.Random(b.content.seed);
    final x0 = b.x0, z0 = b.z0, x1 = x0 + block, z1 = z0 + block;
    g.mat = Mat.paved;
    g.box(
      x0,
      0,
      z0,
      x1,
      0.3,
      z1,
      Pal.sidewalk,
      side: Pal.curb,
      front: Pal.curb,
    );
    g.mat = Mat.plain;
    const y = 0.31;
    final i0x = x0 + walk, i1x = x1 - walk, i0z = z0 + walk, i1z = z1 - walk;
    final inner = i1x - i0x;

    void lot(
      double cx,
      double cz,
      double w,
      double d,
      double rot,
      HouseStyle style,
    ) {
      final l = Lot(
        b,
        b.lots.length,
        cx,
        cz,
        w,
        d,
        rot,
        style,
        b.content.seed + b.lots.length * 7919,
      );
      b.lots.add(l);
      buildLot(l, scene);
    }

    void tree(double x, double z, {int? species}) =>
        _tree(scene, x, z, r, species: species);

    switch (b.content.kind) {
      case BlockKind.empty:
        // Vacant land waiting to be built on (#3).
        _grass(g, i0x, i0z, i1x, i1z, y, r, tile: 5);
      case BlockKind.residential:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        final c = inner / 3;
        for (var a = 0; a < 3; a++) {
          for (var k = 0; k < 3; k++) {
            final cx = i0x + c * (a + 0.5), cz = i0z + c * (k + 0.5);
            if (a == 1 && k == 1) {
              // Shared garden.
              g.mat = Mat.water;
              if (r.nextBool()) {
                g.flat(
                  cx - 2.5,
                  cz - 1.5,
                  cx + 2.5,
                  cz + 1.5,
                  y + 0.03,
                  Pal.water,
                );
              }
              g.mat = Mat.plain;
              tree(cx - 3.5, cz + 3);
              tree(cx + 3.5, cz - 3);
              continue;
            }
            double rot;
            if (k == 2) {
              rot = 0;
            } else if (k == 0) {
              rot = math.pi;
            } else {
              rot = a == 0 ? -math.pi / 2 : math.pi / 2;
            }
            if ((a != 1) && (k != 1) && r.nextBool()) {
              rot = a == 0 ? -math.pi / 2 : math.pi / 2;
            }
            // Driveway towards the street.
            _paved(g, cx - 1, cz - 1, cx + 1, cz + 1, y + 0.01, Pal.path);
            lot(
              cx,
              cz,
              c,
              c,
              rot,
              r.nextInt(5) == 0 ? HouseStyle.shop : HouseStyle.cottage,
            );
          }
        }
      case BlockKind.townhouses:
        _paved(g, i0x, i0z, i1x, i1z, y, Pal.paving);
        _grass(g, i0x + 11.5, i0z + 11.5, i1x - 11.5, i1z - 11.5, y + 0.01, r);
        tree(b.cx, b.cz);
        const dep = 11.0;
        final mid = inner - 2 * dep;
        // Corners (face one of two streets).
        for (final (sx, sz) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
          final cx = sx == 0 ? i0x + dep / 2 : i1x - dep / 2;
          final cz = sz == 0 ? i0z + dep / 2 : i1z - dep / 2;
          final rot = r.nextBool()
              ? (sz == 0 ? math.pi : 0.0)
              : (sx == 0 ? -math.pi / 2 : math.pi / 2);
          lot(
            cx,
            cz,
            dep,
            dep,
            rot,
            r.nextInt(3) == 0 ? HouseStyle.shop : HouseStyle.townhouse,
          );
        }
        final n = (mid / 6).floor();
        final lw = mid / n;
        for (var k = 0; k < n; k++) {
          final u = i0x + dep + lw * (k + 0.5);
          lot(u, i1z - dep / 2, lw, dep, 0, HouseStyle.townhouse);
          lot(u, i0z + dep / 2, lw, dep, math.pi, HouseStyle.townhouse);
          final v = i0z + dep + lw * (k + 0.5);
          lot(i1x - dep / 2, v, lw, dep, math.pi / 2, HouseStyle.townhouse);
          lot(i0x + dep / 2, v, lw, dep, -math.pi / 2, HouseStyle.townhouse);
        }
      case BlockKind.downtown:
        _paved(g, i0x, i0z, i1x, i1z, y, Pal.pavingDark);
        final c = inner / 2;
        for (var a = 0; a < 2; a++) {
          for (var k = 0; k < 2; k++) {
            final rot = r.nextBool()
                ? (k == 0 ? math.pi : 0.0)
                : (a == 0 ? -math.pi / 2 : math.pi / 2);
            lot(
              i0x + c * (a + 0.5),
              i0z + c * (k + 0.5),
              c,
              c,
              rot,
              r.nextInt(4) == 0 ? HouseStyle.apartment : HouseStyle.office,
            );
          }
        }
      case BlockKind.apartments:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        _paved(g, i0x, b.cz - 1.2, i1x, b.cz + 1.2, y + 0.01, Pal.path);
        final c = inner / 2;
        for (var a = 0; a < 2; a++) {
          lot(
            i0x + c * (a + 0.5),
            i0z + 6.5,
            c,
            13,
            math.pi,
            HouseStyle.apartment,
          );
          lot(i0x + c * (a + 0.5), i1z - 6.5, c, 13, 0, HouseStyle.apartment);
        }
        for (var k = 0; k < 4; k++) {
          tree(i0x + 4 + k * 8.5, b.cz + 3.2);
        }
      case BlockKind.park:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        _paved(g, i0x, b.cz - 1.4, i1x, b.cz + 1.4, y + 0.01, Pal.path);
        _paved(g, b.cx - 1.4, i0z, b.cx + 1.4, i1z, y + 0.01, Pal.path);
        // Pond.
        g.mat = Mat.water;
        final px = b.cx + 9, pz = b.cz - 9;
        g.lathe(
          px,
          pz,
          [y + 0.02, y + 0.02],
          [5.5, 0],
          10,
          Pal.water,
          capTop: false,
        );
        g.mat = Mat.plain;
        _add(scene, _fountainS, b.cx, y, b.cz, owner: b);
        for (final (bx, bz, rot) in [
          (b.cx - 6, b.cz + 2.4, 0.0),
          (b.cx + 6, b.cz - 2.4, math.pi),
          (b.cx - 2.4, b.cz - 7, -math.pi / 2),
        ]) {
          _add(scene, _bench, bx, y, bz, rot: rot, owner: b);
        }
        for (var k = 0; k < 16; k++) {
          final tx = i0x + 2 + r.nextDouble() * (inner - 4);
          final tz = i0z + 2 + r.nextDouble() * (inner - 4);
          if ((tx - b.cx).abs() < 3 || (tz - b.cz).abs() < 3) continue;
          if ((tx - px).abs() < 6.5 && (tz - pz).abs() < 6.5) continue;
          tree(tx, tz);
        }
      case BlockKind.plaza:
        g.mat = Mat.paved;
        const tile = 4.25;
        for (var a = 0; a < 8; a++) {
          for (var k = 0; k < 8; k++) {
            g.flat(
              i0x + a * tile,
              i0z + k * tile,
              i0x + (a + 1) * tile,
              i0z + (k + 1) * tile,
              y,
              (a + k).isEven ? Pal.paving : Pal.pavingDark,
            );
          }
        }
        g.mat = Mat.plain;
        g.lathe(
          b.cx,
          b.cz,
          [y + 0.01, y + 0.01],
          [9, 0],
          16,
          0xFFC4B69C,
          capTop: false,
        );
        _add(scene, _fountainL, b.cx, y, b.cz, owner: b);
        for (var k = 0; k < 12; k++) {
          final a = k * math.pi / 6;
          tree(b.cx + math.cos(a) * 11.5, b.cz + math.sin(a) * 11.5);
        }
        for (final (sx, sz) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
          final rot = sz > 0 ? 0.0 : math.pi;
          lot(b.cx + sx * 14, b.cz + sz * 14, 5, 5, rot, HouseStyle.kiosk);
        }
      case BlockKind.fair:
        _paved(g, i0x, i0z, i1x, i1z, y, Pal.path);
        _grass(g, i0x, i0z, i0x + 8, i1z, y + 0.01, r);
        lot(b.cx + 7, b.cz + 7, 18, 18, 0, HouseStyle.circus);
        lot(b.cx + 11, b.cz - 12, 6, 6, 0, HouseStyle.kiosk);
        lot(b.cx + 3, b.cz - 12, 6, 6, 0, HouseStyle.kiosk);
        final wheel = _add(
          scene,
          _wheelMesh,
          b.cx - 7,
          y + 12.5,
          b.cz - 6,
          rot: math.pi / 2 + 0.3,
          owner: b,
        );
        wheel.dynamicLight = true;
        _add(
          scene,
          _wheelBaseMesh,
          b.cx - 7,
          y,
          b.cz - 6,
          rot: math.pi / 2 + 0.3,
          owner: b,
        );
        b.spinners.add(Spinner(wheel, 0.18));
        final car = _add(
          scene,
          _carouselMesh,
          b.cx - 8,
          y,
          b.cz + 10,
          owner: b,
        );
        car.dynamicLight = true;
        b.spinners.add(Spinner(car, 0.6));
        for (var k = 0; k < 4; k++) {
          tree(i0x + 3, i0z + 4 + k * 8.5);
        }
      case BlockKind.farm:
        g.mat = Mat.crop;
        for (var k = 0; k < 6; k++) {
          final fz = i0z + k * inner / 6;
          g.flat(i0x, fz, i1x - 14, fz + inner / 6 - 0.6, y, rgb8(0));
          g.flat(
            i0x,
            fz + inner / 6 - 0.6,
            i1x - 14,
            fz + inner / 6,
            y,
            0xFF8C6B4A,
          );
        }
        g.mat = Mat.plain;
        _grass(g, i1x - 14, i0z, i1x, i1z, y, r);
        lot(i1x - 7, i1z - 9, 14, 18, math.pi / 2, HouseStyle.barn);
        final mill = _mill;
        final mx = i0x + 9.0, mz = i0z + 9.0;
        _add(scene, mill.main, mx, y, mz, rot: 0.4, owner: b)
          ..sx = 0.8
          ..sy = 0.8
          ..sz = 0.8;
        final sails =
            _add(
                scene,
                mill.spinner!,
                mx + math.sin(0.4) * mill.spinnerAt.z * 0.8,
                y + mill.spinnerAt.y * 0.8,
                mz + math.cos(0.4) * mill.spinnerAt.z * 0.8,
                rot: 0.4,
                owner: b,
              )
              ..sx = 0.8
              ..sy = 0.8
              ..sz = 0.8
              ..dynamicLight = true;
        b.spinners.add(Spinner(sails, 0.25, windDriven: true));
        for (var k = 0; k < 3; k++) {
          tree(i1x - 3, i0z + 3 + k * 4, species: 1);
        }
      case BlockKind.supermarket:
        g.mat = Mat.paved;
        g.flat(i0x, b.cz, i1x, i1z, y, Pal.asphaltDark);
        g.mat = Mat.plain;
        for (var k = 0; k < 11; k++) {
          final lx = i0x + 1.5 + k * 3.0;
          g.flat(lx, b.cz + 2, lx + 0.15, b.cz + 7, y + 0.01, Pal.marking);
          g.flat(lx, i1z - 7, lx + 0.15, i1z - 2, y + 0.01, Pal.marking);
        }
        _paved(g, i0x, i0z, i1x, b.cz, y, Pal.paving);
        lot(b.cx, i0z + 9, inner, 17, 0, HouseStyle.supermarket);
        for (var k = 0; k < 10; k++) {
          if (r.nextInt(3) == 0) continue;
          final lx = i0x + 3 + k * 3.0;
          final row = r.nextBool();
          final m = _carMesh(
            r.nextInt(2),
            Pal.cars[r.nextInt(Pal.cars.length)],
          );
          _add(
            scene,
            m,
            lx,
            y,
            row ? b.cz + 4.5 : i1z - 4.5,
            rot: row ? 0 : math.pi,
            owner: b,
          );
        }
      case BlockKind.hospital:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        lot(b.cx, i0z + 8.5, inner, 16, 0, HouseStyle.hospital);
        // Helipad.
        final hx = b.cx + 7, hz = i1z - 8;
        g.flat(hx - 6, hz - 6, hx + 6, hz + 6, y + 0.02, 0xFF4E9AA8);
        g.lathe(
          hx,
          hz,
          [y + 0.04, y + 0.04],
          [4.6, 4.0],
          16,
          0xFFF4F1EA,
          capTop: false,
        );
        g.flat(hx - 1.6, hz - 2, hx - 0.9, hz + 2, y + 0.05, 0xFFF4F1EA);
        g.flat(hx + 0.9, hz - 2, hx + 1.6, hz + 2, y + 0.05, 0xFFF4F1EA);
        g.flat(hx - 0.9, hz - 0.35, hx + 0.9, hz + 0.35, y + 0.05, 0xFFF4F1EA);
        _paved(g, i0x + 2, i1z - 14, i0x + 12, i1z - 2, y + 0.01, Pal.paving);
        _add(scene, _carMesh(2, 0xFFF4F1EA), i0x + 7, y, i1z - 8, owner: b);
        tree(i0x + 3, i1z - 3);
        tree(i0x + 14, i1z - 3);
      case BlockKind.sports:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        final fx0 = i0x + 2, fx1 = i1x - 2, fz0 = i0z + 9, fz1 = i1z - 2;
        g.flat(fx0, fz0, fx1, fz1, y + 0.02, 0xFF4F9A48);
        void line(double a, double b2, double c, double d) =>
            g.flat(a, b2, c, d, y + 0.03, 0xFFF4F1EA);
        line(fx0, fz0, fx1, fz0 + 0.2);
        line(fx0, fz1 - 0.2, fx1, fz1);
        line(fx0, fz0, fx0 + 0.2, fz1);
        line(fx1 - 0.2, fz0, fx1, fz1);
        line(b.cx - 0.1, fz0, b.cx + 0.1, fz1);
        g.lathe(
          b.cx,
          (fz0 + fz1) / 2,
          [y + 0.035, y + 0.035],
          [4, 3.8],
          16,
          0xFFF4F1EA,
          capTop: false,
        );
        for (final gx in [fx0, fx1]) {
          final gz = (fz0 + fz1) / 2;
          _add(
            scene,
            _goalMesh,
            gx,
            y,
            gz,
            rot: gx == fx0 ? math.pi / 2 : -math.pi / 2,
            owner: b,
          );
        }
        lot(b.cx, i0z + 4, inner, 7, 0, HouseStyle.stands);
      case BlockKind.church:
        _grass(g, i0x, i0z, i1x, i1z, y, r);
        _paved(g, b.cx - 1.5, b.cz + 8, b.cx + 1.5, i1z, y + 0.01, Pal.path);
        lot(b.cx, b.cz - 2, 20, 30, 0, HouseStyle.church);
        for (var k = 0; k < 6; k++) {
          tree(i0x + 2.5, i0z + 3 + k * 5.5, species: k.isEven ? 1 : null);
          tree(i1x - 2.5, i0z + 3 + k * 5.5, species: k.isEven ? null : 1);
        }
    }
  }

  static final _bench = buildBench();
  // Prop meshes shared by every block that uses them.
  static final _fountainS = buildFountain(3);
  static final _fountainL = buildFountain(3.6);
  static final _wheelMesh = _ferrisWheel();
  static final _wheelBaseMesh = _ferrisBase();
  static final _carouselMesh = _carousel();
  static final _goalMesh = _goal();
  static final _mill = buildMonument(Monument.windmill);
  static final _lamp = buildLamp();
  final _carMeshes = <int, Mesh>{};
  Mesh _carMesh(int kind, int color) => _carMeshes.putIfAbsent(
    kind * 0x1000000 + (color & 0xFFFFFF),
    () => buildCar(kind, color),
  );

  // Shared tree meshes per (species, variant).
  final _treeMeshes = <int, Mesh>{};

  void _tree(Scene scene, double x, double z, math.Random r, {int? species}) {
    int sp;
    if (species != null && treeStyle == TreeStyle.mixed) {
      sp = species;
    } else {
      switch (treeStyle) {
        case TreeStyle.mixed:
          sp = const [0, 0, 3, 3, 3, 2, 1][r.nextInt(7)];
        case TreeStyle.round:
          sp = 0;
        case TreeStyle.pine:
          sp = 1;
        case TreeStyle.cluster:
          sp = 3;
        case TreeStyle.poplar:
          sp = 2;
      }
    }
    final variant = r.nextInt(4);
    final mesh = _treeMeshes.putIfAbsent(
      sp * 10 + variant,
      () => buildTree(sp, variant),
    );
    final s = 1.05 + r.nextDouble() * 0.4;
    final o = _add(
      scene,
      mesh,
      x,
      0.3,
      z,
      rot: r.nextDouble() * math.pi * 2,
      tint: r.nextDouble(),
    );
    o.sx = o.sy = o.sz = s;
    final crownY = 0.3 + (mesh.maxY * 0.7) * s;
    _cur!.trees.add(
      TreeInfo(
        o,
        crownY,
        1.6 * s,
        sp != 1,
        r.nextDouble() * 6.28,
        sp == 2 ? 1.6 : (sp == 1 ? 0.6 : 1.0),
      ),
    );
  }

  void _buildStreetFurniture(Block b, Scene scene) {
    // Own random stream per block so rebuilding one block is deterministic.
    final r = math.Random(b.content.seed ^ 0x5bd1e995);
    {
      final x0 = b.x0, z0 = b.z0, x1 = x0 + block, z1 = z0 + block;
      // Lamps at corners.
      for (final (lx, lz, rot) in [
        (x0 + 1.0, z0 + 1.0, math.pi * 0.75),
        (x1 - 1.0, z0 + 1.0, math.pi * 0.25),
        (x1 - 1.0, z1 - 1.0, -math.pi * 0.25),
        (x0 + 1.0, z1 - 1.0, -math.pi * 0.75),
      ]) {
        _add(scene, _lamp, lx, 0.3, lz, rot: rot - math.pi / 2, shadow: false);
        // Lamp head: local (0.9, 4.05, 0) rotated.
        final rr = rot - math.pi / 2;
        b.lamps
          ..add(lx + math.cos(rr) * 0.9)
          ..add(4.0)
          ..add(lz - math.sin(rr) * 0.9);
      }
      // Street trees along the four sides.
      final kind = b.content.kind;
      if (kind == BlockKind.plaza ||
          kind == BlockKind.farm ||
          kind == BlockKind.empty) {
        return;
      }
      if (treeDensity <= 0.01) return;
      final spacing = 6.5 / treeDensity;
      for (var u = 6.0; u <= block - 6.0 + 1e-6; u += spacing) {
        if (r.nextInt(6) == 0) continue;
        _tree(scene, x0 + u, z0 + 1.5, r);
        _tree(scene, x0 + u, z1 - 1.5, r);
        _tree(scene, x0 + 1.5, z0 + u, r);
        _tree(scene, x1 - 1.5, z0 + u, r);
      }
    }
  }

  /// Creates the objects for a lot (house or monument).
  void buildLot(Lot l, Scene scene) {
    final b = l.block;
    for (final o in l.objects) {
      scene.objects.remove(o);
      b.objects.remove(o);
    }
    b.spinners.removeWhere((s) => l.objects.contains(s.obj));
    l.objects.clear();
    final mon = l.monument;
    if (l.demolished) {
      // Empty lot (#8): nothing to build.
    } else if (mon == null) {
      final e = l.edits;
      final m = buildHouse(
        l.style,
        l.w,
        l.d,
        l.seed,
        HouseOptions(
          floors: e?.floors,
          facade: e?.facade,
          roof: e?.roof,
          roofKind: e?.roofKind,
        ),
      );
      l.objects.add(
        _add(scene, m, l.cx, 0.3, l.cz, rot: l.rot, owner: l, block: b),
      );
    } else {
      final model = buildMonument(mon);
      final s = (math.min(l.w, l.d) / 12).clamp(0.9, 1.4);
      final main =
          _add(
              scene,
              model.main,
              l.cx,
              0.3,
              l.cz,
              rot: l.rot,
              owner: l,
              block: b,
            )
            ..sx = s
            ..sy = s
            ..sz = s;
      l.objects.add(main);
      if (model.spinner != null) {
        final p = model.spinnerAt;
        final sp =
            _add(
                scene,
                model.spinner!,
                l.cx + (math.cos(l.rot) * p.x + math.sin(l.rot) * p.z) * s,
                0.3 + p.y * s,
                l.cz + (-math.sin(l.rot) * p.x + math.cos(l.rot) * p.z) * s,
                rot: l.rot,
                owner: l,
                block: b,
              )
              ..sx = s
              ..sy = s
              ..sz = s
              ..dynamicLight = true;
        l.objects.add(sp);
        b.spinners.add(Spinner(sp, 0.25, windDriven: true));
      }
    }
    if (_cur == null) {
      spinners
        ..clear()
        ..addAll(blocks.expand((b) => b.spinners));
    }
  }

  static Mesh _ferrisWheel() {
    final b = MeshBuilder(sortParts: true);
    const steel = 0xFFE9E4DA;
    const r = 11.0;
    const n = 16;
    for (final z in const [-0.9, 0.9]) {
      for (var k = 0; k < n; k++) {
        final a0 = k * 2 * math.pi / n, a1 = (k + 1) * 2 * math.pi / n;
        b.beam(
          V3(math.cos(a0) * r, math.sin(a0) * r, z),
          V3(math.cos(a1) * r, math.sin(a1) * r, z),
          0.3,
          steel,
        );
        if (k.isEven) {
          b.beam(
            V3(0, 0, z),
            V3(math.cos(a0) * r, math.sin(a0) * r, z),
            0.15,
            steel,
          );
        }
      }
    }
    const cabins = [0xFFD8402F, 0xFFF2C744, 0xFF3A6EA5, 0xFF3F8F5A];
    for (var k = 0; k < n; k += 2) {
      final a = k * 2 * math.pi / n;
      final cx = math.cos(a) * r, cy = math.sin(a) * r;
      b.mat = Mat.neon;
      b.box(
        cx - 0.8,
        cy - 1.6,
        -0.8,
        cx + 0.8,
        cy - 0.2,
        0.8,
        cabins[(k ~/ 2) % 4],
        bottom: true,
      );
      b.mat = Mat.plain;
    }
    b.box(-0.6, -0.6, -1.2, 0.6, 0.6, 1.2, Pal.darkMetal, bottom: true);
    return b.build();
  }

  static Mesh _ferrisBase() {
    final b = MeshBuilder();
    for (final z in const [-1.6, 1.6]) {
      b.beam(V3(-5, 0, z), V3(0, 12.5, z * 0.7), 0.5, 0xFFB9B4AD);
      b.beam(V3(5, 0, z), V3(0, 12.5, z * 0.7), 0.5, 0xFFB9B4AD);
    }
    b.box(-6, 0, -3, 6, 0.4, 3, 0xFF9AA3AD);
    return b.build();
  }

  static Mesh _carousel() {
    final b = MeshBuilder();
    b.lathe(0, 0, [0, 0.6], [4.5, 4.5], 12, 0xFFE9E3D6, capTop: true);
    b.cylinder(0, 0, 0.6, 4, 0.4, 6, 0xFFD4AF37);
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      final x = math.cos(a) * 3.3, z = math.sin(a) * 3.3;
      b.cylinder(x, z, 0.6, 3.6, 0.07, 3, 0xFFD4AF37);
      b.box(
        x - 0.25,
        1.2,
        z - 0.6,
        x + 0.25,
        2.0,
        z + 0.6,
        k.isEven ? 0xFFF5EFE4 : 0xFF8C5E3C,
      );
    }
    b.mat = Mat.neon;
    b.lathe(
      0,
      0,
      [3.6, 3.9, 5.5],
      [5.0, 5.0, 0],
      12,
      0xFFD8402F,
      segColors: const [0xFFD8402F, 0xFFF5EFE4],
      capTop: false,
    );
    b.mat = Mat.plain;
    return b.build();
  }

  static Mesh _goal() {
    final b = MeshBuilder();
    b.box(-0.1, 0, -3.6, 0.1, 2.4, -3.4, 0xFFF4F1EA);
    b.box(-0.1, 0, 3.4, 0.1, 2.4, 3.6, 0xFFF4F1EA);
    b.box(-0.1, 2.4, -3.6, 0.1, 2.6, 3.6, 0xFFF4F1EA, bottom: true);
    return b.build();
  }

  // ---------------------------------------------------------------------
  // Shadows and height map.

  void updateShadows(Scene scene) {
    final light = scene.light;
    if (light.shadowAlpha < 0.01) {
      scene.shadows = Float32List(0);
      scene.groundVersion++;
      return;
    }
    final ly = math.max(light.sy, 0.18);
    final px = -light.sx / ly, pz = -light.sz / ly;
    final winter = light.season == Season.winter;
    final out = _ShadowOut();
    for (final o in scene.objects) {
      if (!o.castShadow || !o.visible || o.mesh.maxY < 0.4) continue;
      if (o.build < 0.999) continue; // still under construction (#6)
      final cache = _shadowPts[o.mesh] ??= _ShadowPts(o.mesh);
      final cr = math.cos(o.rot), sr = math.sin(o.rot);
      final gy = o.y + 0.02;
      final groups = winter ? cache.winter : cache.all;
      for (final pts in groups) {
        if (pts.length ~/ 3 > _hx.length) {
          _hx = Float64List(pts.length);
          _hz = Float64List(pts.length);
          _idx = Int32List(pts.length);
          _hull = Int32List(pts.length * 2);
        }
        var n = 0;
        for (var k = 0; k < pts.length; k += 3) {
          final lx = pts[k] * o.sx, lz = pts[k + 2] * o.sz;
          final h = o.y + pts[k + 1] * o.sy - gy;
          final hh = h > 0 ? h : 0.0;
          _hx[n] = o.x + cr * lx + sr * lz + px * hh;
          _hz[n] = o.z - sr * lx + cr * lz + pz * hh;
          n++;
        }
        _hullFan(n, gy, out);
      }
    }
    scene.shadows = out.toList();
    scene.groundVersion++;
  }

  static final _shadowPts = Expando<_ShadowPts>();
  static Float64List _hx = Float64List(256), _hz = Float64List(256);
  static Int32List _idx = Int32List(256), _hull = Int32List(512);

  /// Convex hull (monotone chain) of the first [n] points in [_hx]/[_hz],
  /// emitted as a triangle fan at height [y].
  static void _hullFan(int n, double y, _ShadowOut out) {
    if (n < 3) return;
    final xs = _hx, zs = _hz, idx = _idx, hull = _hull;
    for (var i = 0; i < n; i++) {
      idx[i] = i;
    }
    // Insertion sort by x then z (n is small).
    for (var i = 1; i < n; i++) {
      final v = idx[i];
      var j = i - 1;
      while (j >= 0 &&
          (xs[idx[j]] > xs[v] || (xs[idx[j]] == xs[v] && zs[idx[j]] > zs[v]))) {
        idx[j + 1] = idx[j];
        j--;
      }
      idx[j + 1] = v;
    }
    double cross(int o, int a, int b) =>
        (xs[a] - xs[o]) * (zs[b] - zs[o]) - (zs[a] - zs[o]) * (xs[b] - xs[o]);
    var h = 0;
    for (var k = 0; k < n; k++) {
      final i = idx[k];
      while (h >= 2 && cross(hull[h - 2], hull[h - 1], i) <= 0) {
        h--;
      }
      hull[h++] = i;
    }
    final lower = h + 1;
    for (var k = n - 2; k >= 0; k--) {
      final i = idx[k];
      while (h >= lower && cross(hull[h - 2], hull[h - 1], i) <= 0) {
        h--;
      }
      hull[h++] = i;
    }
    h--;
    if (h < 3) return;
    final a = hull[0];
    for (var k = 1; k < h - 1; k++) {
      out.tri(
        xs[a],
        zs[a],
        xs[hull[k]],
        zs[hull[k]],
        xs[hull[k + 1]],
        zs[hull[k + 1]],
        y,
      );
    }
  }

  void _buildHeights(Scene scene) {
    hw = width.ceil() + 1;
    hd = depth.ceil() + 1;
    heights = Float32List(hw * hd);
    void fill(double x0, double z0, double x1, double z1, double h) {
      final a0 = ((x0 + width / 2)).floor().clamp(0, hw - 1);
      final a1 = ((x1 + width / 2)).ceil().clamp(0, hw - 1);
      final b0 = ((z0 + depth / 2)).floor().clamp(0, hd - 1);
      final b1 = ((z1 + depth / 2)).ceil().clamp(0, hd - 1);
      for (var b = b0; b < b1; b++) {
        for (var a = a0; a < a1; a++) {
          final k = b * hw + a;
          if (heights[k] < h) heights[k] = h;
        }
      }
    }

    for (final b in blocks) {
      fill(b.x0, b.z0, b.x0 + block, b.z0 + block, 0.3);
      for (final l in b.lots) {
        for (final o in l.objects) {
          final m = o.mesh;
          final cr = math.cos(o.rot).abs(), sr = math.sin(o.rot).abs();
          final ex = (m.maxX - m.minX) / 2 * o.sx,
              ez = (m.maxZ - m.minZ) / 2 * o.sz;
          final wx = cr * ex + sr * ez, wz = sr * ex + cr * ez;
          // Shrink a little so leaves can still fall past edges/roof slopes.
          fill(
            o.x - wx * 0.8,
            o.z - wz * 0.8,
            o.x + wx * 0.8,
            o.z + wz * 0.8,
            o.y + m.maxY * o.sy * 0.85,
          );
        }
      }
    }
  }

  void refreshHeights(Scene scene) => _buildHeights(scene);

  double heightAt(double x, double z) {
    final a = (x + width / 2).floor(), b = (z + depth / 2).floor();
    if (a < 0 || b < 0 || a >= hw || b >= hd) return -100;
    return heights[b * hw + a];
  }

  bool onBoard(double x, double z) =>
      x.abs() < width / 2 && z.abs() < depth / 2;

  Block? blockAt(double x, double z) {
    for (final b in blocks) {
      if (x >= b.x0 && x <= b.x0 + block && z >= b.z0 && z <= b.z0 + block) {
        return b;
      }
    }
    return null;
  }
}

/// Growable triangle buffer for shadow geometry.
class _ShadowOut {
  var _d = Float32List(9 * 4096);
  var _n = 0;

  void tri(
    double x0,
    double z0,
    double x1,
    double z1,
    double x2,
    double z2,
    double y,
  ) {
    if (_n + 9 > _d.length) {
      _d = Float32List(_d.length * 2)..setRange(0, _n, _d);
    }
    final d = _d;
    d[_n] = x0;
    d[_n + 1] = y;
    d[_n + 2] = z0;
    d[_n + 3] = x1;
    d[_n + 4] = y;
    d[_n + 5] = z1;
    d[_n + 6] = x2;
    d[_n + 7] = y;
    d[_n + 8] = z2;
    _n += 9;
  }

  Float32List toList() =>
      Float32List.fromList(Float32List.sublistView(_d, 0, _n));
}

/// Per-mesh points used to cast its ground shadow, cached once.
///
/// Projecting along the light only shifts points of equal height by the same
/// vector, so the shadow hull of a mesh is the hull of the per-height hulls
/// of its part-box corners. Keeping just those keeps the per-light-change
/// work small (#4). Meshes whose parts are depth sorted (monuments) keep
/// one hull per part so arches and lattices stay open.
class _ShadowPts {
  final List<Float32List> all;
  final List<Float32List> winter;

  _ShadowPts._(this.all, this.winter);

  factory _ShadowPts(Mesh m) {
    List<Float32List> collect(bool skipFoliage) {
      final groups = <Float32List>[];
      // Height level -> bounding rect (x0, z0, x1, z1) of corners there.
      final levels = <int, Float64List>{};
      final b = m.partBox;
      for (var p = 0; p < m.partCount; p++) {
        final t0 = m.partStart[p], t1 = m.partStart[p + 1];
        if (t0 >= t1) continue;
        if (skipFoliage && m.mat[t0] == Mat.foliage) continue;
        final k = p * 6;
        if (b[k + 4] < 0.3) continue;
        if (m.sortParts) {
          final c = <double>[];
          for (final y in [b[k + 1], b[k + 4]]) {
            for (final x in [b[k], b[k + 3]]) {
              for (final z in [b[k + 2], b[k + 5]]) {
                c.addAll([x, y, z]);
              }
            }
          }
          groups.add(Float32List.fromList(c));
          continue;
        }
        for (final y in [b[k + 1], b[k + 4]]) {
          final r = levels.putIfAbsent(
            (y * 20).round(),
            () => Float64List.fromList([1e9, 1e9, -1e9, -1e9]),
          );
          if (b[k] < r[0]) r[0] = b[k];
          if (b[k + 2] < r[1]) r[1] = b[k + 2];
          if (b[k + 3] > r[2]) r[2] = b[k + 3];
          if (b[k + 5] > r[3]) r[3] = b[k + 5];
        }
      }
      if (levels.isNotEmpty) {
        // The shadow is a convex hull anyway, so each level's bounding
        // rectangle is enough and avoids sorting points per mesh.
        final pts = Float32List(levels.length * 12);
        var n = 0;
        levels.forEach((key, r) {
          final y = key / 20;
          for (final (x, z) in [
            (r[0], r[1]),
            (r[2], r[1]),
            (r[2], r[3]),
            (r[0], r[3]),
          ]) {
            pts[n++] = x;
            pts[n++] = y;
            pts[n++] = z;
          }
        });
        groups.add(pts);
      }
      return groups;
    }

    return _ShadowPts._(collect(false), collect(true));
  }
}
