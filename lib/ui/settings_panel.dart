import 'package:flutter/material.dart';

import '../engine/lighting.dart';
import '../world/city.dart';
import '../world/world.dart';
import 'controls.dart';

class SettingsPanel extends StatefulWidget {
  final World world;
  final ValueNotifier<String> stats;
  const SettingsPanel({super.key, required this.world, required this.stats});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _open = true;
  int? _nx, _nz;
  double? _trees;

  World get w => widget.world;

  static const _lightGradient = LinearGradient(
    colors: [
      Color(0xFF2A3360),
      Color(0xFF6B5A8E),
      Color(0xFFF0A86A),
      Color(0xFFFFF1D6),
      Color(0xFFFFE7B8),
      Color(0xFFF2A65A),
      Color(0xFFC0607A),
      Color(0xFF2A3360),
    ],
  );

  String _meters(int blocks) =>
      '${(blocks * City.pitch + City.road).round()} m';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: w,
      builder: (context, _) {
        return GlassPanel(
          width: 264,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _open ? _body() : const SizedBox(width: 236),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = !_open),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: UI.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'SETTINGS',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: UI.text,
              ),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: _open ? 0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more, size: 18, color: UI.dim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final light = w.light;
    final nx = _nx ?? w.city.nx, nz = _nz ?? w.city.nz;
    final trees = _trees ?? w.treeDensity;
    final buttons = <Widget>[
      PanelButton(icon: Icons.air, label: 'Gust', onTap: w.gust),
      PanelButton(
        icon: Icons.cyclone,
        label: 'Leaf devil',
        onTap: w.leafDevil,
        active: w.weather.devil != null,
      ),
      PanelButton(
        icon: w.sound ? Icons.volume_up : Icons.volume_off,
        label: 'Sound',
        active: w.sound,
        onTap: () {
          w.sound = !w.sound;
          setState(() {});
        },
      ),
      PanelButton(
        icon: Icons.music_note,
        label: 'Music',
        active: w.music,
        onTap: () {
          w.music = !w.music;
          setState(() {});
        },
      ),
      PanelButton(
        icon: Icons.blur_linear,
        label: 'Tilt-shift',
        active: w.tiltShift,
        onTap: () {
          w.tiltShift = !w.tiltShift;
          setState(() {});
        },
      ),
      PanelButton(
        icon: Icons.park,
        label: 'Switch trees',
        onTap: w.switchTrees,
      ),
      PanelButton(icon: Icons.crop_free, label: 'Whole map', onTap: w.wholeMap),
      PanelButton(
        icon: Icons.open_with,
        label: 'Move blocks',
        active: w.moveBlocks,
        onTap: w.toggleMoveBlocks,
      ),
      PanelButton(
        icon: Icons.restart_alt,
        label: 'Reset blocks',
        onTap: w.resetBlocks,
      ),
      PanelButton(
        icon: Icons.home_work_outlined,
        label: 'Reset houses',
        onTap: w.resetHouses,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text('ATMOSPHERE', style: UI.section),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Light',
          valueText: light.label,
          slider: TownSlider(
            value: w.hour,
            min: 0,
            max: 24,
            gradient: _lightGradient,
            onChanged: (v) => w.hour = v,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Season', style: UI.label)),
            Text(_cap(w.season.name), style: UI.value),
          ],
        ),
        const SizedBox(height: 6),
        SegmentedChips(
          labels: const ['Spring', 'Summer', 'Autumn', 'Winter'],
          selected: w.season.index,
          onSelected: (i) => w.season = Season.values[i],
        ),
        const SizedBox(height: 10),
        LabeledSlider(
          label: 'Wind',
          valueText: '${w.wind.base.toStringAsFixed(1)} m/s',
          slider: TownSlider(
            value: w.wind.base,
            min: 0,
            max: 20,
            onChanged: (v) {
              w.wind.base = v;
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            WindCompass(
              fromDeg: w.wind.fromDeg,
              onChanged: (v) {
                w.wind.fromDeg = v;
                setState(() {});
              },
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wind from', style: UI.label),
                const SizedBox(height: 2),
                Text(
                  w.wind.compassName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: UI.text,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: const Color(0x1FFFFFFF)),
        const SizedBox(height: 10),
        const Text('TOWN', style: UI.section),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LabeledSlider(
                label: 'Width',
                valueText: _meters(nx),
                slider: TownSlider(
                  value: nx.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  onChanged: (v) => setState(() => _nx = v.round()),
                  onChangeEnd: (v) {
                    _nx = null;
                    w.resize(v.round(), w.city.nz);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledSlider(
                label: 'Depth',
                valueText: _meters(nz),
                slider: TownSlider(
                  value: nz.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  onChanged: (v) => setState(() => _nz = v.round()),
                  onChangeEnd: (v) {
                    _nz = null;
                    w.resize(w.city.nx, v.round());
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Traffic & people',
          valueText: '×${w.trafficAmount.toStringAsFixed(2)}',
          slider: TownSlider(
            value: w.trafficAmount,
            min: 0,
            max: 3,
            onChanged: w.setTraffic,
          ),
        ),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Street trees',
          valueText: '×${_fmt(trees)}',
          slider: TownSlider(
            value: trees,
            min: 0,
            max: 3,
            divisions: 12,
            onChanged: (v) => setState(() => _trees = v),
            onChangeEnd: (v) {
              _trees = null;
              w.setTreeDensity(v);
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LabeledSlider(
                label: 'Leaves',
                valueText: '${(w.weather.leaves * 100).round()}%',
                slider: TownSlider(
                  value: w.weather.leaves,
                  min: 0,
                  max: 3,
                  onChanged: (v) {
                    w.weather.leaves = v;
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledSlider(
                label: 'Leaf size',
                valueText: '×${w.weather.leafSize.toStringAsFixed(1)}',
                slider: TownSlider(
                  value: w.weather.leafSize,
                  min: 0.5,
                  max: 3,
                  onChanged: (v) {
                    w.weather.leafSize = v;
                    setState(() {});
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: const Color(0x1FFFFFFF)),
        const SizedBox(height: 10),
        for (var i = 0; i < buttons.length; i += 2) ...[
          Row(
            children: [
              Expanded(child: buttons[i]),
              const SizedBox(width: 6),
              Expanded(child: buttons[i + 1]),
            ],
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 4),
        ValueListenableBuilder<String>(
          valueListenable: widget.stats,
          builder: (context, s, _) => Text(
            s,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9.5,
              height: 1.4,
              color: UI.faint,
            ),
          ),
        ),
      ],
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
