import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'engine/lighting.dart';
import 'world/buildings.dart';
import 'world/city.dart';
import 'world/monuments.dart';
import 'world/world.dart';

/// Built only with `--dart-define=DEBUG_HOOK=true`: QA scripts drive the
/// scene through `window.__tileCity` because the canvas has no DOM (#2).
const debugHookEnabled = bool.fromEnvironment('DEBUG_HOOK');

void installDebugHook(World w) {
  String stats() {
    final r = w.renderer.stats;
    return jsonEncode({
      'fps': w.fps,
      'cpuMs': r.cpuMs,
      'simMs': w.simMs,
      'triangles': r.triangles,
      'drawCalls': r.drawCalls,
      'objects': w.scene.objects.length,
      'blocks': w.city.blocks.length,
      'houses': w.city.houseCount,
      'kinds': [for (final b in w.city.blocks) b.content.kind.name],
      'particles': w.scene.particles.alive,
      'building': w.building,
      'hour': w.hour,
      'season': w.season.name,
    });
  }

  /// `cmd('{"op":"hour","v":12}')` → stats JSON.
  String cmd(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final v = m['v'];
    switch (m['op']) {
      case 'hour':
        w.hour = (v as num).toDouble();
      case 'season':
        w.season = Season.values.byName(v as String);
      case 'resize':
        w.resize(v[0] as int, v[1] as int);
      case 'tilt':
        w.tiltShift = v as bool;
      case 'orbit':
        w.orbit((v[0] as num).toDouble(), (v[1] as num).toDouble());
      case 'zoom':
        w.zoom((v as num).toDouble());
      case 'wholeMap':
        w.wholeMap();
      case 'advance':
        // Simulate [v] seconds at 60 Hz (swiftshader is too slow to wait).
        for (var t = 0.0; t < (v as num); t += 1 / 60) {
          w.update(1 / 60);
        }
      case 'gust':
        w.gust();
      case 'devil':
        w.leafDevil();
      case 'build':
        // [blockIndex, lotIndex, monumentName or null]
        final l = w.city.blocks[v[0] as int].lots[v[1] as int];
        final name = v[2] as String?;
        w.setMonument(
          l,
          name == null
              ? null
              : Monument.values.firstWhere((m) => m.name == name),
        );
      case 'camera':
        final c = w.renderer.cam, mv = v as Map<String, dynamic>;
        c.tx = (mv['tx'] as num?)?.toDouble() ?? c.tx;
        c.tz = (mv['tz'] as num?)?.toDouble() ?? c.tz;
        c.dist = (mv['dist'] as num?)?.toDouble() ?? c.dist;
        c.yaw = (mv['yaw'] as num?)?.toDouble() ?? c.yaw;
        c.pitch = (mv['pitch'] as num?)?.toDouble() ?? c.pitch;
      case 'lot':
        // [blockIndex, lotIndex] -> moves the camera to it.
        final l = w.city.blocks[v[0] as int].lots[v[1] as int];
        w.renderer.cam
          ..tx = l.cx
          ..tz = l.cz
          ..dist = 90;
      case 'mode':
        w.setMode(ToolMode.values.byName(v as String));
      case 'tile':
        // [i, j, kindName] (#7)
        w.setTileKind(
          w.city.blockAtCell(v[0] as int, v[1] as int),
          BlockKind.values.byName(v[2] as String),
        );
      case 'selectTile':
        w.selectTile(w.city.blockAtCell(v[0] as int, v[1] as int));
      case 'selectLot':
        // [blockIndex, lotIndex]
        w.selectLot(w.city.blocks[v[0] as int].lots[v[1] as int]);
      case 'edit':
        // [blockIndex, lotIndex, {floors, facade, roof, roofKind, style,
        //  rotSteps, demolished}] (#8)
        final l = w.city.blocks[v[0] as int].lots[v[1] as int];
        final m = v[2] as Map<String, dynamic>;
        w.editLot(l, (e) {
          if (m['floors'] != null) e.floors = m['floors'] as int;
          if (m['facade'] != null) e.facade = m['facade'] as int;
          if (m['roof'] != null) e.roof = m['roof'] as int;
          if (m['roofKind'] != null) {
            e.roofKind = RoofKind.values.byName(m['roofKind'] as String);
          }
          if (m['style'] != null) {
            e.style = HouseStyle.values.byName(m['style'] as String);
          }
          if (m['rotSteps'] != null) e.rotSteps = m['rotSteps'] as int;
          if (m['demolished'] != null) e.demolished = m['demolished'] as bool;
        });
      case 'undo':
        w.undo();
      case 'smooth':
        w.smoothEdges = v as bool;
        w.autoSmooth = false;
      case 'supersample':
        w.supersampleFactor = (v as num).toDouble();
      case 'lod':
        w.renderer.lodScale = (v as num).toDouble();
    }
    return stats();
  }

  final hook = JSObject();
  hook['stats'] = (() => stats().toJS).toJS;
  hook['cmd'] = ((JSString s) => cmd(s.toDart).toJS).toJS;
  globalContext['__tileCity'] = hook;
}
