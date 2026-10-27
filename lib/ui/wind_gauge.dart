import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../world/simulation.dart';
import 'controls.dart';

/// Bottom-left live wind readout.
class WindGauge extends StatelessWidget {
  final Wind wind;
  const WindGauge({super.key, required this.wind});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size.square(30),
            painter: _DialPainter(wind.fromDeg),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    wind.speed.toStringAsFixed(1),
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: UI.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'm/s',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 9.5,
                      color: UI.dim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 84,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (wind.speed / 25).clamp(0.0, 1.0),
                    backgroundColor: const Color(0x30FFFFFF),
                    valueColor: const AlwaysStoppedAnimation(UI.accent),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                Wind.beaufort(wind.speed),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 8.5,
                  letterSpacing: 1.2,
                  color: UI.dim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double fromDeg;
  _DialPainter(this.fromDeg);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x2AFFFFFF));
    final a = fromDeg * math.pi / 180;
    final d = Offset(math.sin(a), -math.cos(a));
    final p = Offset(-d.dy, d.dx);
    final tip = c - d * (r * 0.6);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        c.dx + d.dx * r * 0.5 + p.dx * r * 0.35,
        c.dy + d.dy * r * 0.5 + p.dy * r * 0.35,
      )
      ..lineTo(c.dx + d.dx * r * 0.25, c.dy + d.dy * r * 0.25)
      ..lineTo(
        c.dx + d.dx * r * 0.5 - p.dx * r * 0.35,
        c.dy + d.dy * r * 0.5 - p.dy * r * 0.35,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = UI.accent);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.fromDeg != fromDeg;
}
