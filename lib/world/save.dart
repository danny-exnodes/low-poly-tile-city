import 'dart:convert';

import '../engine/lighting.dart';
import 'buildings.dart';
import 'city.dart';
import 'monuments.dart';
import 'props.dart';
import 'world.dart';

/// Compact, versioned town state for autosave and share links (#9).
///
/// Untouched tiles are regenerated from (seed, base size), so only tiles
/// that differ from the generated town are written.
abstract final class TownState {
  static const version = 1;

  static Map<String, dynamic> capture(World w) {
    final c = w.city;
    final cells = <List<Object>>[];
    for (var k = 0; k < c.layout.length; k++) {
      final i = k % c.nx, j = k ~/ c.nx;
      final content = c.layout[k];
      final (kind, seed) = c.defaultContent(i, j);
      if (content.kind == kind &&
          content.seed == seed &&
          content.lots.isEmpty) {
        continue;
      }
      cells.add([
        k,
        content.kind.index,
        content.seed.toRadixString(36),
        if (content.lots.isNotEmpty)
          {for (final e in content.lots.entries) '${e.key}': _lot(e.value)},
      ]);
    }
    return {
      'v': version,
      's': c.seed.toRadixString(36),
      'b': [c.baseNx, c.baseNz],
      'n': [c.nx, c.nz],
      'c': cells,
      'o': [
        (w.hour * 10).round(),
        w.season.index,
        (w.wind.base * 10).round(),
        w.wind.fromDeg.round(),
        (w.trafficAmount * 100).round(),
        (w.treeDensity * 100).round(),
        (w.weather.leaves * 100).round(),
        (w.weather.leafSize * 10).round(),
        c.treeStyle.index,
        w.tiltShift ? 1 : 0,
      ],
    };
  }

  static Map<String, Object> _lot(LotOverride e) => {
    if (e.style != null) 's': e.style!.index,
    if (e.floors != null) 'f': e.floors!,
    if (e.facade != null) 'w': (e.facade! & 0xFFFFFF).toRadixString(16),
    if (e.roof != null) 'r': (e.roof! & 0xFFFFFF).toRadixString(16),
    if (e.roofKind != null) 'k': e.roofKind!.index,
    if (e.rotSteps != 0) 't': e.rotSteps,
    if (e.seed != null) 'e': e.seed!.toRadixString(36),
    if (e.demolished) 'd': 1,
    if (e.monument != null) 'm': e.monument!.index,
  };

  static LotOverride _readLot(Map<String, dynamic> m) {
    int? hex(Object? v) =>
        v == null ? null : 0xFF000000 | int.parse(v as String, radix: 16);
    return LotOverride()
      ..style = m['s'] == null ? null : HouseStyle.values[m['s'] as int]
      ..floors = m['f'] as int?
      ..facade = hex(m['w'])
      ..roof = hex(m['r'])
      ..roofKind = m['k'] == null ? null : RoofKind.values[m['k'] as int]
      ..rotSteps = (m['t'] as int?) ?? 0
      ..seed = m['e'] == null ? null : int.parse(m['e'] as String, radix: 36)
      ..demolished = m['d'] == 1
      ..monument = m['m'] == null ? null : Monument.values[m['m'] as int];
  }

  /// Rebuilds [w] from [state]. Returns false (and leaves [w] alone) when
  /// the state is from another version or malformed.
  static bool apply(World w, Map<String, dynamic> state) {
    try {
      if (state['v'] != version) return false;
      final seed = int.parse(state['s'] as String, radix: 36);
      final base = (state['b'] as List).cast<int>();
      final size = (state['n'] as List).cast<int>();
      final city = City(base[0], base[1], seed);
      if (size[0] != base[0] || size[1] != base[1]) {
        city.resize(size[0], size[1]);
      }
      for (final cell in state['c'] as List) {
        final k = cell[0] as int;
        final content = city.layout[k];
        content.kind = BlockKind.values[cell[1] as int];
        content.seed = int.parse(cell[2] as String, radix: 36);
        content.lots.clear();
        if (cell.length > 3) {
          (cell[3] as Map<String, dynamic>).forEach((lot, v) {
            content.lots[int.parse(lot)] = _readLot(v as Map<String, dynamic>);
          });
        }
      }
      final o = (state['o'] as List).cast<int>();
      city.treeStyle = TreeStyle.values[o[8]];
      w.loadCity(
        city,
        hour: o[0] / 10,
        season: Season.values[o[1]],
        windBase: o[2] / 10,
        windFrom: o[3].toDouble(),
        traffic: o[4] / 100,
        trees: o[5] / 100,
        leaves: o[6] / 100,
        leafSize: o[7] / 10,
        tiltShift: o[9] == 1,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String encode(World w) =>
      base64Url.encode(utf8.encode(jsonEncode(capture(w)))).replaceAll('=', '');

  static Map<String, dynamic>? decode(String s) {
    try {
      final pad = s.length % 4 == 0 ? '' : '=' * (4 - s.length % 4);
      return jsonDecode(utf8.decode(base64Url.decode(s + pad)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
