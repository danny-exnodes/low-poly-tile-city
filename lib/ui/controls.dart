import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Visual constants for the warm glass panels.
abstract final class UI {
  static const panel = Color(0xD94A3A30);
  static const panelBorder = Color(0x33FFE9D2);
  static const text = Color(0xFFF3E9DC);
  static const dim = Color(0xFFB7A797);
  static const faint = Color(0xFF8E7E70);
  static const accent = Color(0xFFE9894A);
  static const button = Color(0x26FFFFFF);
  static const buttonOn = Color(0xFFB8673D);
  static const track = Color(0x40FFFFFF);
  static const fill = Color(0xFFE9DCCB);

  static const label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    color: dim,
    height: 1.2,
  );
  static const section = TextStyle(
    fontFamily: 'Inter',
    fontSize: 9.5,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w600,
    color: faint,
  );
  static const value = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 11,
    color: text,
    height: 1.2,
  );
  static const title = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: text,
  );
}

/// Rounded translucent panel with a backdrop blur.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double? width;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: UI.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: UI.panelBorder, width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Thin slider with a round thumb; optional gradient track.
class TownSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Gradient? gradient;
  final int? divisions;
  const TownSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.gradient,
    this.divisions,
  });

  @override
  State<TownSlider> createState() => _TownSliderState();
}

class _TownSliderState extends State<TownSlider> {
  bool _active = false;

  double _valueAt(double dx, double w) {
    final t = ((dx - 8) / (w - 16)).clamp(0.0, 1.0);
    var v = widget.min + (widget.max - widget.min) * t;
    final d = widget.divisions;
    if (d != null && d > 0) {
      final step = (widget.max - widget.min) / d;
      v = widget.min + ((v - widget.min) / step).round() * step;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              setState(() => _active = true);
              widget.onChanged(_valueAt(d.localPosition.dx, w));
            },
            onHorizontalDragUpdate: (d) =>
                widget.onChanged(_valueAt(d.localPosition.dx, w)),
            onHorizontalDragEnd: (_) {
              setState(() => _active = false);
              widget.onChangeEnd?.call(widget.value);
            },
            onTapUp: (d) {
              final v = _valueAt(d.localPosition.dx, w);
              widget.onChanged(v);
              widget.onChangeEnd?.call(v);
            },
            child: SizedBox(
              height: 22,
              width: w,
              child: CustomPaint(
                painter: _SliderPainter(
                  (widget.value - widget.min) / (widget.max - widget.min),
                  widget.gradient,
                  _active,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double t;
  final Gradient? gradient;
  final bool active;
  _SliderPainter(this.t, this.gradient, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x0 = 8.0, x1 = size.width - 8;
    final x = x0 + (x1 - x0) * t.clamp(0.0, 1.0);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTRB(x0, y - 1.5, x1, y + 1.5),
      const Radius.circular(2),
    );
    if (gradient != null) {
      canvas.drawRRect(
        track,
        Paint()..shader = gradient!.createShader(track.outerRect),
      );
    } else {
      canvas.drawRRect(track, Paint()..color = UI.track);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, y - 1.5, x, y + 1.5),
          const Radius.circular(2),
        ),
        Paint()..color = UI.fill,
      );
    }
    canvas.drawCircle(
      Offset(x, y + 1),
      active ? 8 : 7,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      Offset(x, y),
      active ? 7.5 : 6.5,
      Paint()..color = const Color(0xFFFBF6EE),
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.t != t || old.active != active || old.gradient != gradient;
}

/// Label on the left, monospace value on the right, slider below.
class LabeledSlider extends StatelessWidget {
  final String label, valueText;
  final Widget slider;
  const LabeledSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: UI.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(valueText, style: UI.value),
          ],
        ),
        const SizedBox(height: 2),
        slider,
      ],
    );
  }
}

class PanelButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const PanelButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  State<PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<PanelButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? UI.buttonOn
        : (_hover ? const Color(0x3AFFFFFF) : UI.button);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: widget.active
                    ? const Color(0x55FFC08A)
                    : const Color(0x1AFFFFFF),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 14, color: UI.text),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      height: 1.1,
                      color: UI.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SegmentedChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  const SegmentedChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? UI.buttonOn : UI.button,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: i == selected
                          ? const Color(0x55FFC08A)
                          : const Color(0x1AFFFFFF),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      color: UI.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Draggable compass for the wind direction ("from").
class WindCompass extends StatelessWidget {
  final double fromDeg;
  final ValueChanged<double> onChanged;
  final double size;
  const WindCompass({
    super.key,
    required this.fromDeg,
    required this.onChanged,
    this.size = 46,
  });

  void _set(Offset p) {
    final c = size / 2;
    final a = math.atan2(p.dx - c, -(p.dy - c)) * 180 / math.pi;
    onChanged((a + 360) % 360);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onPanStart: (d) => _set(d.localPosition),
        onPanUpdate: (d) => _set(d.localPosition),
        onTapDown: (d) => _set(d.localPosition),
        child: CustomPaint(
          size: Size.square(size),
          painter: _CompassPainter(fromDeg),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double fromDeg;
  _CompassPainter(this.fromDeg);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x22FFFFFF));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 1,
    );
    final tick = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      final l = k.isEven ? 5.0 : 3.0;
      canvas.drawLine(
        c + Offset(math.sin(a), -math.cos(a)) * (r - l),
        c + Offset(math.sin(a), -math.cos(a)) * (r - 1),
        tick,
      );
    }
    final a = fromDeg * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final perp = Offset(-dir.dy, dir.dx);
    // Arrow points from the source towards the centre (where wind goes).
    final tail = c + dir * (r - 6);
    final head = c - dir * (r * 0.45);
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..color = UI.accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final path = Path()
      ..moveTo(head.dx - dir.dx * 5, head.dy - dir.dy * 5)
      ..lineTo(
        head.dx + dir.dx * 2 + perp.dx * 4.5,
        head.dy + dir.dy * 2 + perp.dy * 4.5,
      )
      ..lineTo(
        head.dx + dir.dx * 2 - perp.dx * 4.5,
        head.dy + dir.dy * 2 - perp.dy * 4.5,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = UI.accent);
    canvas.drawCircle(tail, 2.5, Paint()..color = UI.accent);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.fromDeg != fromDeg;
}
