import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../world/world.dart';

/// Full-screen 3D view with orbit / pan / zoom / pick input.
class CityViewport extends StatefulWidget {
  final World world;
  final Listenable frame;
  const CityViewport({super.key, required this.world, required this.frame});

  @override
  State<CityViewport> createState() => _CityViewportState();
}

class _CityViewportState extends State<CityViewport> {
  final _pointers = <int, Offset>{};
  Offset? _downAt;
  bool _moved = false;
  bool _panMode = false;
  double? _pinchDist;

  World get w => widget.world;

  bool get _shift =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _downAt = e.localPosition;
      _moved = false;
      _panMode =
          e.buttons == kSecondaryMouseButton ||
          e.buttons == kMiddleMouseButton ||
          _shift;
    } else {
      _moved = true;
      _pinchDist = null;
    }
  }

  void _move(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    if (_downAt != null && (e.localPosition - _downAt!).distance > 4) {
      _moved = true;
    }
    if (!_moved) return;
    if (_pointers.length >= 2) {
      // Two-finger: pinch to zoom, drag to pan.
      final pts = _pointers.values.toList();
      final d = (pts[0] - pts[1]).distance;
      if (_pinchDist != null && d > 0) w.zoom(_pinchDist! / d);
      _pinchDist = d;
      w.pan(e.delta.dx / 2, e.delta.dy / 2);
      return;
    }
    if (_panMode) {
      w.pan(e.delta.dx, e.delta.dy);
    } else {
      w.orbit(e.delta.dx, e.delta.dy);
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      if (!_moved && e is PointerUpEvent && _downAt != null) {
        w.tap(e.localPosition.dx, e.localPosition.dy);
      }
      _downAt = null;
      _pinchDist = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          w.zoom(math.exp(e.scrollDelta.dy * 0.0012));
        } else if (e is PointerScaleEvent) {
          w.zoom(1 / e.scale);
        }
      },
      onPointerPanZoomUpdate: (e) {
        if (e.scale != 1) {
          w.zoom(1 / math.pow(e.scale, 0.08));
        }
        w.orbit(-e.panDelta.dx * 0.6, -e.panDelta.dy * 0.6);
      },
      child: MouseRegion(
        cursor: w.moveBlocks
            ? SystemMouseCursors.move
            : SystemMouseCursors.basic,
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _ScenePainter(w, widget.frame),
            isComplex: true,
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final World world;
  _ScenePainter(this.world, Listenable frame) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    world.renderer.render(
      canvas,
      size,
      world.scene,
      tiltShift: world.tiltShift,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}
