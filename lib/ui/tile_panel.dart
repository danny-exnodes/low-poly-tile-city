import 'package:flutter/material.dart';

import '../world/city.dart';
import '../world/world.dart';
import 'controls.dart';
import 'house_panel.dart';

/// Label and icon for each kind of tile.
const tileKinds = <BlockKind, (String, IconData)>{
  BlockKind.empty: ('Empty land', Icons.crop_square),
  BlockKind.residential: ('Cottages', Icons.cottage),
  BlockKind.townhouses: ('Townhouses', Icons.holiday_village),
  BlockKind.downtown: ('Downtown', Icons.location_city),
  BlockKind.apartments: ('Apartments', Icons.apartment),
  BlockKind.park: ('Park', Icons.park),
  BlockKind.plaza: ('Plaza', Icons.water_drop),
  BlockKind.fair: ('Fairground', Icons.attractions),
  BlockKind.farm: ('Farm', Icons.agriculture),
  BlockKind.supermarket: ('Supermarket', Icons.local_grocery_store),
  BlockKind.hospital: ('Hospital', Icons.local_hospital),
  BlockKind.sports: ('Sports field', Icons.sports_soccer),
  BlockKind.church: ('Church', Icons.church),
};

/// Build mode: change what a whole tile is (#7).
class TilePanel extends StatelessWidget {
  final World world;
  final Block block;
  const TilePanel({super.key, required this.world, required this.block});

  @override
  Widget build(BuildContext context) {
    final w = world;
    final kind = block.content.kind;
    return GlassPanel(
      width: 252,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'TILE ${block.i + 1}-${block.j + 1}',
            onClose: w.deselectTile,
          ),
          const SizedBox(height: 2),
          Text(tileKinds[kind]!.$1, style: UI.title),
          const SizedBox(height: 10),
          const Text('BUILD AS', style: UI.section),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final e in tileKinds.entries)
                SizedBox(
                  width: 72,
                  child: _KindChip(
                    icon: e.value.$2,
                    label: e.value.$1,
                    active: e.key == kind,
                    onTap: () => w.setTileKind(block, e.key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PanelButton(
                  icon: Icons.casino_outlined,
                  label: 'Variant',
                  onTap: () => w.tileVariant(block),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PanelButton(
                  icon: Icons.layers_clear_outlined,
                  label: 'Clear',
                  onTap: () => w.clearTile(block),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          UndoButton(world: w),
          const SizedBox(height: 6),
          const Text(
            'Click a building on the tile to edit it.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: UI.faint,
            ),
          ),
        ],
      ),
    );
  }
}

class UndoButton extends StatelessWidget {
  final World world;
  const UndoButton({super.key, required this.world});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: world.canUndo ? 1 : 0.45,
      child: PanelButton(
        icon: Icons.undo,
        label: 'Undo  (Ctrl+Z)',
        onTap: world.undo,
      ),
    );
  }
}

class _KindChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _KindChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_KindChip> createState() => _KindChipState();
}

class _KindChipState extends State<_KindChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 50,
          decoration: BoxDecoration(
            color: widget.active
                ? UI.buttonOn
                : (_hover ? const Color(0x3AFFFFFF) : UI.button),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.active
                  ? const Color(0x55FFC08A)
                  : const Color(0x1AFFFFFF),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 16, color: UI.text),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  color: UI.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
