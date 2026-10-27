// Performance budget for the renderer and the city builder (#4).
//
// Runs on the Dart VM: numbers are not browser numbers, but they move
// together with them and are stable enough to catch regressions in CI.
// Budgets carry a 1.5x margin for slower CI machines.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:low_poly_tile_city/engine/lighting.dart';
import 'package:low_poly_tile_city/world/world.dart';

const _size = ui.Size(1440, 860);

/// Target (ms) for each measurement; CI fails above target * 1.5.
const budgets = <String, double>{
  'render still': 5,
  'render orbiting': 6,
  'light change': 8,
  'shadows': 5,
  'city build': 30,
  'swap 2 blocks': 10,
};

/// Median of 5 batch averages, after a warm-up batch (JIT).
double _avg(void Function() f, int n) {
  final batch = (n / 5).ceil();
  for (var i = 0; i < batch; i++) {
    f();
  }
  final runs = <double>[];
  for (var r = 0; r < 5; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < batch; i++) {
      f();
    }
    runs.add(sw.elapsedMicroseconds / batch / 1000);
  }
  runs.sort();
  return runs[2];
}

void main() {
  test('performance budget', () {
    final w = World()..finishConstruction();
    for (var i = 0; i < 300; i++) {
      w.update(1 / 60);
    }
    void render() {
      final rec = ui.PictureRecorder();
      // Tilt-shift is left out: its toImageSync is a GPU op in the browser
      // but a software raster in flutter_tester. Browser timing: perf.cjs.
      w.renderer.render(ui.Canvas(rec), _size, w.scene, tiltShift: false);
      rec.endRecording();
    }

    for (var i = 0; i < 100; i++) {
      render();
      if (i.isEven) w.orbit(1, 0);
    }
    final results = <String, double>{};
    results['render still'] = _avg(render, 60);
    results['render orbiting'] = _avg(() {
      w.orbit(3, 0);
      render();
    }, 60);
    var h = 17.0;
    results['light change'] = _avg(() {
      h += 0.05;
      w.hour = h;
      w.update(0.2); // past the drag throttle so the change applies
      render();
    }, 20);
    w.season = Season.autumn;
    results['shadows'] = _avg(() => w.city.updateShadows(w.scene), 10);
    results['city build'] = _avg(() => w.city.build(w.scene), 5);
    final a = w.city.blocks[0], b = w.city.blocks[6];
    results['swap 2 blocks'] = _avg(() => w.swapBlocks(a, b), 5);

    final stats = w.renderer.stats;
    final lines = <String>[
      for (final e in results.entries)
        '${e.key.padRight(16)} ${e.value.toStringAsFixed(2).padLeft(7)} ms'
            '  (target ${budgets[e.key]} ms)',
      'triangles drawn  ${stats.triangles}',
      'objects          ${w.scene.objects.length}',
      'shadow tris      ${w.scene.shadows.length ~/ 9}',
    ];
    // ignore: avoid_print
    print('\n${lines.join('\n')}');
    for (final e in results.entries) {
      expect(e.value, lessThan(budgets[e.key]! * 1.5), reason: e.key);
    }
  });
}
