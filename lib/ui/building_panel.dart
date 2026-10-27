import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../world/buildings.dart';
import '../world/city.dart';
import '../world/props.dart';
import '../world/world.dart';
import 'controls.dart';
import 'house_panel.dart';
import 'tile_panel.dart';

const _roofColors = [
  0xFF4A4E5A, 0xFF3D4047, 0xFFB5583A, 0xFF7A4A35, 0xFF5D6470, 0xFFA34A33, //
  0xFF4F7A5A, 0xFF8E8A85,
];

/// Build mode: edit one building (#8).
class BuildingPanel extends StatelessWidget {
  final World world;
  final Lot lot;
  const BuildingPanel({super.key, required this.world, required this.lot});

  @override
  Widget build(BuildContext context) {
    final w = world;
    final e = lot.edits;
    final editable =
        editableStyles.containsKey(lot.style) &&
        lot.monument == null &&
        !lot.demolished;
    final range = editableStyles[lot.style];
    final mesh = lot.objects.isEmpty ? null : lot.objects.first.mesh;
    // Current floor count: chosen, or estimated from the generated height.
    final fh = lot.style == HouseStyle.office
        ? 3.2
        : lot.style == HouseStyle.apartment
        ? 3.0
        : lot.style == HouseStyle.cottage
        ? 2.9
        : 3.1;
    final floors =
        e?.floors ??
        (mesh == null || range == null
            ? 0
            : (mesh.maxY / fh).floor().clamp(range.$1, range.$2));
    final big = math.min(lot.w, lot.d) >= 10;

    return GlassPanel(
      width: 252,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: 'BUILDING', onClose: w.deselect),
          const SizedBox(height: 2),
          Text(lot.name, style: UI.title),
          if (lot.demolished) ...[
            const SizedBox(height: 10),
            const Text('BUILD HERE', style: UI.section),
            const SizedBox(height: 6),
            _styleChips(w, lot, big),
          ] else if (editable) ...[
            const SizedBox(height: 10),
            const Text('STYLE', style: UI.section),
            const SizedBox(height: 6),
            _styleChips(w, lot, big),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Text('Floors', style: UI.label)),
                _Stepper(
                  value: floors,
                  min: range!.$1,
                  max: range.$2,
                  onChanged: (v) => w.editLot(lot, (x) => x.floors = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Walls', style: UI.label),
            const SizedBox(height: 4),
            _Swatches(
              colors: [...Pal.facades.take(10), 0xFFDCE1E6, 0xFF6E879E],
              selected: e?.facade,
              onPick: (c) => w.editLot(lot, (x) => x.facade = c),
            ),
            const SizedBox(height: 8),
            const Text('Roof', style: UI.label),
            const SizedBox(height: 4),
            _Swatches(
              colors: _roofColors,
              selected: e?.roof,
              onPick: (c) => w.editLot(lot, (x) => x.roof = c),
            ),
            if (roofKindsFor[lot.style] case final kinds?) ...[
              const SizedBox(height: 6),
              SegmentedChips(
                labels: [for (final k in kinds) k.label],
                selected: e?.roofKind == null
                    ? -1
                    : kinds.indexOf(e!.roofKind!),
                onSelected: (i) => w.editLot(lot, (x) => x.roofKind = kinds[i]),
              ),
            ],
          ],
          const SizedBox(height: 10),
          if (!lot.demolished) ...[
            Row(
              children: [
                Expanded(
                  child: PanelButton(
                    icon: Icons.rotate_90_degrees_ccw,
                    label: lot.square ? 'Rotate 90°' : 'Rotate 180°',
                    onTap: () => w.editLot(
                      lot,
                      (x) =>
                          x.rotSteps = (x.rotSteps + (lot.square ? 1 : 2)) % 4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: PanelButton(
                    icon: Icons.casino_outlined,
                    label: 'Variant',
                    onTap: () => w.editLot(
                      lot,
                      (x) => x.seed = math.Random().nextInt(1 << 30),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            PanelButton(
              icon: Icons.delete_outline,
              label: 'Demolish',
              onTap: () => w.editLot(lot, (x) => x.demolished = true),
            ),
            const SizedBox(height: 10),
            const Text('MONUMENT', style: UI.section),
            const SizedBox(height: 6),
            MonumentPicker(world: w, lot: lot),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: PanelButton(
                  icon: Icons.home_outlined,
                  label: 'Original',
                  onTap: () {
                    if (lot.edits != null) w.setMonument(lot, null);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: UndoButton(world: w)),
            ],
          ),
          const SizedBox(height: 6),
          LotStatus(world: w, lot: lot),
        ],
      ),
    );
  }

  Widget _styleChips(World w, Lot lot, bool big) {
    final styles = [
      HouseStyle.cottage,
      HouseStyle.townhouse,
      HouseStyle.shop,
      if (big) HouseStyle.apartment,
      if (big) HouseStyle.office,
    ];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final s in styles)
          SizedBox(
            width: 108,
            height: 28,
            child: PanelButton(
              icon: _styleIcon(s),
              label: s.label,
              active: !lot.demolished && lot.style == s,
              onTap: () => w.editLot(lot, (x) {
                x
                  ..style = s
                  ..demolished = false
                  ..floors = null
                  ..roofKind = null;
              }),
            ),
          ),
      ],
    );
  }

  static IconData _styleIcon(HouseStyle s) => switch (s) {
    HouseStyle.cottage => tileKinds[BlockKind.residential]!.$2,
    HouseStyle.townhouse => tileKinds[BlockKind.townhouses]!.$2,
    HouseStyle.shop => Icons.storefront,
    HouseStyle.apartment => tileKinds[BlockKind.apartments]!.$2,
    _ => tileKinds[BlockKind.downtown]!.$2,
  };
}

class _Stepper extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) => Opacity(
    opacity: enabled ? 1 : 0.35,
    child: SizedBox(
      width: 30,
      height: 26,
      child: PanelButton(icon: icon, label: '', onTap: enabled ? onTap : () {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _btn(Icons.remove, value > min, () => onChanged(value - 1)),
        SizedBox(
          width: 34,
          child: Text('$value', textAlign: TextAlign.center, style: UI.value),
        ),
        _btn(Icons.add, value < max, () => onChanged(value + 1)),
      ],
    );
  }
}

class _Swatches extends StatelessWidget {
  final List<int> colors;
  final int? selected;
  final ValueChanged<int> onPick;
  const _Swatches({
    required this.colors,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final c in colors)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Color(c),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: c == selected ? UI.accent : const Color(0x55FFFFFF),
                    width: c == selected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
