import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:low_poly_tile_city/engine/lighting.dart';
import 'package:low_poly_tile_city/engine/scene.dart';
import 'package:low_poly_tile_city/world/buildings.dart';
import 'package:low_poly_tile_city/world/city.dart';
import 'package:low_poly_tile_city/world/monuments.dart';
import 'package:low_poly_tile_city/world/world.dart';

void _run(World w, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    w.update(1 / 60);
  }
}

void _render(World w) {
  final rec = ui.PictureRecorder();
  w.renderer.render(ui.Canvas(rec), const ui.Size(1280, 800), w.scene);
  rec.endRecording();
}

int _count(Particles p, int state) {
  var n = 0;
  for (var i = 0; i < p.count; i++) {
    if (p.state[i] == state) n++;
  }
  return n;
}

void main() {
  test('city builds with houses, trees, cars and people', () {
    final w = World()..finishConstruction();
    expect(w.city.blocks.length, 25);
    expect(w.city.houseCount, greaterThan(100));
    expect(w.city.trees.length, greaterThan(200));
    expect(w.traffic.cars, isNotEmpty);
    expect(w.traffic.people, isNotEmpty);
    _render(w);
    expect(w.renderer.stats.triangles, greaterThan(10000));
  });

  test('autumn leaves fall and settle; leaf devil lifts them', () {
    final w = World()..finishConstruction();
    _run(w, 20);
    final p = w.scene.particles;
    expect(_count(p, 1), greaterThan(20), reason: 'airborne leaves');
    expect(_count(p, 2), greaterThan(100), reason: 'leaves on the ground');
    w.leafDevil();
    expect(w.weather.devil, isNotNull);
    _run(w, 4);
    final d = w.weather.devil!;
    var near = 0;
    for (var i = 0; i < p.count; i++) {
      if (p.state[i] != 1) continue;
      final dx = p.x[i] - d.x, dz = p.z[i] - d.z;
      if (dx * dx + dz * dz < 200 && p.y[i] > 2) near++;
    }
    expect(near, greaterThan(30), reason: 'leaves swirling in the devil');
  });

  test('cars stay on the road grid', () {
    final w = World()..finishConstruction();
    _run(w, 30);
    final half = w.city.width / 2;
    for (final c in w.traffic.cars) {
      expect(c.obj.x.abs(), lessThan(half));
      expect(c.obj.z.abs(), lessThan(w.city.depth / 2));
      expect(
        w.city.blockAt(c.obj.x, c.obj.z),
        isNull,
        reason: 'car drove into a block',
      );
    }
  });

  test('every monument builds and animates in', () {
    final w = World()..finishConstruction();
    final lot = w.city.blocks.expand((b) => b.lots).first;
    for (final m in Monument.values) {
      w.setMonument(lot, m);
      expect(w.building, isTrue);
      _run(w, 3.5);
      expect(w.building, isFalse);
      expect(lot.name, m.label);
      _render(w);
    }
    w.setMonument(lot, null);
    _run(w, 3.5);
    expect(lot.monument, isNull);
  });

  test('seasons, night, resize and block swaps', () {
    final w = World()..finishConstruction();
    for (final s in Season.values) {
      w.season = s;
      w.hour = 23;
      _run(w, 1);
      _render(w);
    }
    w.resize(7, 4);
    expect(w.city.blocks.length, 28);
    _run(w, 1);
    w.toggleMoveBlocks();
    final a = w.city.blocks[0], b = w.city.blocks[5];
    final ka = a.content.kind, kb = b.content.kind;
    w.tap(-1, -1); // misses the board: nothing selected
    expect(w.moveFrom, isNull);
    w.city.swap(a, b);
    expect(w.city.layout[0].kind, kb);
    expect(w.city.layout[5].kind, ka);
    w.resetBlocks();
    expect(w.city.layout[0].kind, ka);
    _run(w, 1);
    _render(w);
  });

  test('frame cost stays reasonable', () {
    final w = World()..finishConstruction();
    _run(w, 5);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      w.update(1 / 60);
      _render(w);
    }
    final ms = sw.elapsedMilliseconds / 30;
    // ignore: avoid_print
    print(
      'avg frame cpu: ${ms.toStringAsFixed(1)} ms, '
      '${w.renderer.stats.triangles} triangles, '
      '${w.scene.particles.alive} particles',
    );
    expect(ms, lessThan(100));
  });

  test('block kinds all appear at a larger size', () {
    final w = World()..finishConstruction();
    w.resize(8, 8);
    final kinds = w.city.blocks.map((b) => b.content.kind).toSet();
    expect(kinds, containsAll([BlockKind.plaza, BlockKind.park]));
    expect(kinds.length, greaterThan(8));
  });

  test('growing the map adds only empty land (#3)', () {
    final w = World()..finishConstruction();
    final houses = w.city.houseCount;
    final kinds = [for (final b in w.city.blocks) b.content.kind];
    w.resize(6, 5);
    expect(w.city.blocks.length, 30);
    final added = w.city.blocks.where((b) => b.i == 5).toList();
    expect(added.map((b) => b.content.kind).toSet(), {BlockKind.empty});
    expect(added.every((b) => b.lots.isEmpty), isTrue);
    expect(w.city.houseCount, houses);
    // Old blocks untouched.
    for (var j = 0; j < 5; j++) {
      for (var i = 0; i < 5; i++) {
        expect(w.city.blockAtCell(i, j).content.kind, kinds[j * 5 + i]);
      }
    }
    // Shrinking keeps what was cut and gives it back when growing again.
    final lastRow = [for (var i = 0; i < 6; i++) w.city.blockAtCell(i, 4)];
    w.resize(6, 4);
    expect(w.city.blocks.length, 24);
    w.resize(6, 5);
    for (var i = 0; i < 6; i++) {
      expect(w.city.blockAtCell(i, 4).content, same(lastRow[i].content));
    }
    expect(w.city.houseCount, houses);
    // Reset blocks keeps the new land empty.
    w.resetBlocks();
    expect(
      w.city.blocks.where((b) => b.i == 5).map((b) => b.content.kind).toSet(),
      {BlockKind.empty},
    );
  });

  test('swapping blocks rebuilds only those two (#4)', () {
    final w = World()..finishConstruction();
    final a = w.city.blocks[0], b = w.city.blocks[7];
    final ka = a.content.kind, kb = b.content.kind;
    final untouched = w.city.blocks[3];
    final keep = List.of(untouched.objects);
    w.swapBlocks(a, b);
    expect(w.city.blockAtCell(0, 0).content.kind, kb);
    expect(w.city.blockAtCell(2, 1).content.kind, ka);
    expect(identical(w.city.blocks[3], untouched), isTrue);
    for (final o in keep) {
      expect(w.scene.objects.contains(o), isTrue);
    }
    // Old buildings shrink away (#6); afterwards none is left behind.
    _run(w, 1);
    for (final o in a.objects) {
      expect(w.scene.objects.contains(o), isFalse);
    }
  });

  test('buildings rise part by part, bottom first (#6)', () {
    final w = World();
    expect(w.building, isTrue, reason: 'intro construction on start');
    _run(w, 0.5);
    w.tap(10, 10); // a click skips the intro
    expect(w.building, isFalse);
    final lot = w.city.blocks.expand((b) => b.lots).first;
    w.setMonument(lot, Monument.tokyoTower);
    final o = lot.objects.first;
    expect(o.build, 0);
    final seen = <double>[];
    for (var i = 0; i < 200 && w.building; i++) {
      w.update(1 / 60);
      seen.add(o.build);
    }
    expect(w.building, isFalse);
    expect(o.build, 1);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    // Part ranks go bottom to top.
    final m = o.mesh, rank = m.partRank;
    for (var p = 0; p < m.partCount; p++) {
      for (var q = 0; q < m.partCount; q++) {
        if (rank[p] < rank[q]) {
          expect(
            m.partBox[p * 6 + 1],
            lessThanOrEqualTo(m.partBox[q * 6 + 1] + 0.05),
          );
        }
      }
    }
    // Shadow comes back once built.
    expect(w.scene.shadows.length, greaterThan(0));
  });

  test('supersampling switches itself off on slow machines (#5)', () {
    final w = World()..finishConstruction();
    _run(w, 3.1);
    w.smoothEdges = true;
    w.autoSmooth = true;
    for (var i = 0; i < 3; i++) {
      w.reportFps(30);
    }
    expect(w.smoothEdges, isTrue, reason: 'needs 2 s of slow frames');
    w.reportFps(60); // a good sample resets the count
    for (var i = 0; i < 4; i++) {
      w.reportFps(30);
    }
    expect(w.smoothEdges, isFalse);
    expect(w.autoSmooth, isFalse);
  });

  test(
    'soft lighting keeps noon below white and AO darkens wall bases (#5)',
    () {
      final w = World()..finishConstruction();
      w.hour = 12.5;
      _run(w, 0.3);
      _render(w);
      final house = w.city.blocks
          .expand((b) => b.lots)
          .firstWhere((l) => l.style.name == 'townhouse')
          .objects
          .first;
      final lit = house.lit!, m = house.mesh;
      var maxC = 0;
      for (var t = 0; t < m.triCount; t++) {
        for (var v = 0; v < 3; v++) {
          final c = lit[t * 3 + v];
          if (c == 0) continue;
          maxC = [
            maxC,
            (c >> 16) & 255,
            (c >> 8) & 255,
            c & 255,
          ].reduce((a, b) => a > b ? a : b);
        }
      }
      expect(maxC, lessThan(255), reason: 'no blown-out channels at noon');
      // Bottom of a wall is darker than its top.
      final ao = m.ao;
      var low = 0, high = 0;
      for (var t = 0; t < m.triCount; t++) {
        if (m.nrm[t * 3 + 1].abs() > 0.5) continue;
        for (var v = 0; v < 3; v++) {
          final y = m.pos[t * 9 + v * 3 + 1];
          if (y < 0.2) low = ao[t * 3 + v];
          if (y > 4) high = ao[t * 3 + v];
        }
      }
      expect(low, lessThan(high));
    },
  );

  test('tile tools: change kind, variant, clear, undo, reset (#7)', () {
    final w = World()..finishConstruction();
    w.resize(6, 5);
    final empty = w.city.blockAtCell(5, 0);
    expect(empty.content.kind, BlockKind.empty);
    w.setTileKind(empty, BlockKind.park);
    _run(w, 4);
    final park = w.city.blockAtCell(5, 0);
    expect(park.content.kind, BlockKind.park);
    expect(park.trees, isNotEmpty);
    expect(w.building, isFalse);
    // Variant keeps the kind but changes the seed.
    final seed = park.content.seed;
    w.tileVariant(park);
    expect(w.city.blockAtCell(5, 0).content.seed, isNot(seed));
    w.clearTile(w.city.blockAtCell(5, 0));
    expect(w.city.blockAtCell(5, 0).lots, isEmpty);
    // Undo three times: back to empty land.
    w.undo();
    w.undo();
    expect(w.city.blockAtCell(5, 0).content.kind, BlockKind.park);
    expect(w.city.blockAtCell(5, 0).content.seed, seed);
    w.undo();
    expect(w.city.blockAtCell(5, 0).content.kind, BlockKind.empty);
    // Reset blocks restores the generated kind of an edited original tile.
    final first = w.city.blockAtCell(0, 0);
    final kind0 = first.content.kind;
    w.setTileKind(first, BlockKind.empty);
    expect(w.city.blockAtCell(0, 0).content.kind, BlockKind.empty);
    w.resetBlocks();
    expect(w.city.blockAtCell(0, 0).content.kind, kind0);
  });

  test('building tools: floors, colour, roof, rotate, demolish (#8)', () {
    final w = World()..finishConstruction();
    final lot = w.city.blocks
        .expand((b) => b.lots)
        .firstWhere((l) => l.style == HouseStyle.townhouse);
    final tris0 = lot.objects.first.mesh.triCount;
    w.editLot(lot, (e) => e.floors = 3);
    final h3 = lot.objects.first.mesh.maxY;
    w.editLot(lot, (e) => e.floors = 5);
    final h5 = lot.objects.first.mesh.maxY;
    expect(h5 - h3, closeTo(2 * 3.1, 0.01));
    w.editLot(lot, (e) => e.facade = 0xFF123456);
    expect(lot.objects.first.mesh.col.contains(0xFF123456.toSigned(32)), isTrue);
    w.editLot(lot, (e) => e.roofKind = RoofKind.flat);
    expect(lot.edits!.roofKind, RoofKind.flat);
    final rot = lot.objects.first.rot;
    w.editLot(lot, (e) => e.rotSteps += lot.square ? 1 : 2);
    expect(
      lot.objects.first.rot,
      closeTo(rot + (lot.square ? 1 : 2) * math.pi / 2, 1e-9),
    );
    w.editLot(lot, (e) => e.demolished = true);
    expect(lot.objects, isEmpty);
    expect(lot.name, 'Empty lot');
    // Undo everything back to the generated house.
    for (var i = 0; i < 6; i++) {
      w.undo();
    }
    final again = w.city.blocks
        .expand((b) => b.lots)
        .firstWhere(
          (l) =>
              l.index == lot.index &&
              l.block.i == lot.block.i &&
              l.block.j == lot.block.j,
        );
    expect(again.edits, isNull);
    expect(again.objects.first.mesh.triCount, tris0);
    // Reset houses clears edits.
    w.editLot(again, (e) => e.floors = 6);
    w.resetHouses();
    expect(w.city.blocks.every((b) => b.content.lots.isEmpty), isTrue);
  });
}
