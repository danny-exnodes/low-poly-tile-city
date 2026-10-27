import 'package:flutter/material.dart';

import '../world/city.dart';
import '../world/monuments.dart';
import '../world/world.dart';
import 'controls.dart';

/// Shows the selected house and lets you replace it with a monument.
class HousePanel extends StatefulWidget {
  final World world;
  final Lot lot;
  const HousePanel({super.key, required this.world, required this.lot});

  @override
  State<HousePanel> createState() => _HousePanelState();
}

class _HousePanelState extends State<HousePanel> {
  bool _open = false;
  int _hover = -1;

  @override
  void didUpdateWidget(HousePanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.lot, widget.lot)) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.world;
    final lot = widget.lot;
    final mon = lot.monument;
    return GlassPanel(
      width: 232,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('HOUSE', style: UI.section)),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: w.deselect,
                  child: const Icon(Icons.close, size: 15, color: UI.dim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(lot.name, style: UI.title),
          const SizedBox(height: 10),
          const Text('MONUMENT', style: UI.section),
          const SizedBox(height: 6),
          _dropdown(mon),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open ? _list(mon) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: PanelButton(
              icon: Icons.home_outlined,
              label: 'Original',
              active: false,
              onTap: () {
                if (lot.monument != null) w.setMonument(lot, null);
                setState(() => _open = false);
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            w.isBuilding(lot)
                ? 'building…'
                : '${lot.style.label} · block ${lot.block.i + 1}-${lot.block.j + 1}',
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 9.5,
              color: UI.faint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(Monument? mon) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0x30000000),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _open ? UI.accent : const Color(0x33FFFFFF),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  mon?.label ?? 'Choose a monument…',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: mon == null ? UI.dim : UI.text,
                  ),
                ),
              ),
              Icon(
                _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 18,
                color: UI.dim,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(Monument? current) {
    final w = widget.world;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x40000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in Monument.values)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = m.index),
              onExit: (_) => setState(() => _hover = -1),
              child: GestureDetector(
                onTap: () {
                  w.setMonument(widget.lot, m);
                  setState(() => _open = false);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: m == current
                        ? UI.buttonOn
                        : _hover == m.index
                        ? const Color(0x22FFFFFF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    m.label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      color: UI.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
