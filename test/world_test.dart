import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:low_poly_tile_city/engine/lighting.dart';
import 'package:low_poly_tile_city/engine/scene.dart';
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
    final w = World();
    expect(w.city.blocks.length, 25);
    expect(w.city.houseCount, greaterThan(100));
    expect(w.city.trees.length, greaterThan(200));
    expect(w.traffic.cars, isNotEmpty);
    expect(w.traffic.people, isNotEmpty);
    _render(w);
    expect(w.renderer.stats.triangles, greaterThan(10000));
  });

  test('autumn leaves fall and settle; leaf devil lifts them', () {
    final w = World();
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
    final w = World();
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
    final w = World();
    final lot = w.city.blocks.expand((b) => b.lots).first;
    for (final m in Monument.values) {
      w.setMonument(lot, m);
      expect(w.building, isTrue);
      _run(w, 2.2);
      expect(w.building, isFalse);
      expect(lot.name, m.label);
      _render(w);
    }
    w.setMonument(lot, null);
    _run(w, 2.2);
    expect(lot.monument, isNull);
  });

  test('seasons, night, resize and block swaps', () {
    final w = World();
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
    final w = World();
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
    final w = World();
    w.resize(8, 8);
    final kinds = w.city.blocks.map((b) => b.content.kind).toSet();
    expect(kinds, containsAll([BlockKind.plaza, BlockKind.park]));
    expect(kinds.length, greaterThan(8));
  });
}
