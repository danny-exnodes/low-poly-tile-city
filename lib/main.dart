import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'audio/audio_engine.dart';
import 'debug_hook.dart';
import 'ui/controls.dart';
import 'ui/building_panel.dart';
import 'ui/house_panel.dart';
import 'ui/tile_panel.dart';
import 'world/city.dart';
import 'ui/settings_panel.dart';
import 'ui/viewport.dart';
import 'ui/wind_gauge.dart';
import 'web_bridge.dart';
import 'world/save.dart';
import 'world/world.dart';

void main() {
  // Suppress the browser context menu so right-drag can pan.
  web.document.addEventListener(
    'contextmenu',
    ((web.Event e) => e.preventDefault()).toJS,
  );
  runApp(const TileCityApp());
}

class TileCityApp extends StatelessWidget {
  const TileCityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low-Poly Tile City',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: UI.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const CityScreen(),
    );
  }
}

class CityScreen extends StatefulWidget {
  const CityScreen({super.key});

  @override
  State<CityScreen> createState() => _CityScreenState();
}

class _CityScreenState extends State<CityScreen>
    with SingleTickerProviderStateMixin {
  final world = World();
  final audio = AudioEngine();
  final frame = ValueNotifier<int>(0);
  final stats = ValueNotifier<String>('');
  final gauge = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _statT = 0;
  int _frames = 0;

  final toast = ValueNotifier<String?>(null);
  Timer? _saveTimer, _toastTimer;
  String? _lastSaved;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    if (debugHookEnabled) installDebugHook(world);
    _restore();
    // Autosave a few seconds after anything changes (#9).
    _saveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _save());
    WidgetsBinding.instance.addPostFrameCallback((_) => WebBridge.hideLoader());
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    // Phones: no tilt-shift by default (#11).
    if (view.physicalSize.width / view.devicePixelRatio < 640) {
      world.tiltShift = false;
    }
    // High-DPI screens hide jaggies already; supersampling there only costs.
    final dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    world.smoothEdges = dpr < 1.5;
    world.autoSmooth = world.smoothEdges;
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final sw = Stopwatch()..start();
    world.update(dt);
    world.simMs = world.simMs * 0.9 + sw.elapsedMicroseconds / 1000 * 0.1;
    audio.tick(world);
    frame.value++;
    _frames++;
    _statT += dt;
    if (_statT >= 0.5) {
      world.reportFps(_frames / _statT);
      _frames = 0;
      _statT = 0;
      final r = world.renderer.stats;
      final c = world.city;
      stats.value =
          '${world.buildingBlocks > 0 ? 'building ${world.buildingBlocks} blocks… · ' : ''}'
          '${c.nx * c.nz} blocks · ${c.houseCount} houses · '
          '${world.fps.round()} fps\n${r.drawCalls} draw calls · '
          '${_k(r.triangles)} triangles\n'
          'cpu ${r.cpuMs.toStringAsFixed(1)} ms render · ${world.simMs.toStringAsFixed(1)} ms sim';
    }
    if (_frames % 6 == 0) gauge.value++;
  }

  /// Shared link first, then the autosave, else a fresh town (#9).
  void _restore() {
    final shared = WebBridge.sharedTown();
    final saved = shared ?? WebBridge.loadSaved();
    if (saved == null) return;
    final state = TownState.decode(saved);
    if (state != null && TownState.apply(world, state)) {
      _lastSaved = saved;
      if (shared != null) _showToast('Opened a shared town');
    }
  }

  void _save() {
    final code = TownState.encode(world);
    if (code == _lastSaved) return;
    _lastSaved = code;
    WebBridge.save(code);
  }

  Future<void> _share() async {
    final url = WebBridge.shareLink(TownState.encode(world));
    final ok = await WebBridge.copy(url);
    _showToast(
      ok ? 'Link copied — share your town!' : 'Link is in the address bar',
    );
  }

  void _showToast(String text) {
    toast.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      toast.value = null;
    });
  }

  static String _k(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  void dispose() {
    _saveTimer?.cancel();
    _toastTimer?.cancel();
    _ticker.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            world.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): world.undo,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            world.setMode(ToolMode.view),
      },
      child: Focus(autofocus: true, child: _scaffold(compact)),
    );
  }

  Widget _scaffold(bool compact) {
    final context = this.context;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1914),
      body: Stack(
        children: [
          Positioned.fill(
            child: CityViewport(world: world, frame: frame),
          ),
          // House / building / tile panel.
          Positioned(
            left: compact ? 8 : 16,
            top: compact ? 8 : 16,
            right: compact ? 8 : null,
            bottom: compact ? 120 : 90,
            child: Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: world,
                  builder: (context, _) {
                    final lot = world.selected;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(-0.05, 0),
                            end: Offset.zero,
                          ).animate(a),
                          child: c,
                        ),
                      ),
                      child: _leftPanel(lot),
                    );
                  },
                ),
              ),
            ),
          ),
          // Settings.
          if (compact)
            // Phones: settings become a bottom sheet, collapsed at first
            // (#11).
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                  ),
                  child: SingleChildScrollView(
                    child: SettingsPanel(
                      world: world,
                      stats: stats,
                      onShare: _share,
                      compact: true,
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 16,
              top: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: SingleChildScrollView(
                  child: SettingsPanel(
                    world: world,
                    stats: stats,
                    onShare: _share,
                  ),
                ),
              ),
            ),
          // Wind gauge.
          if (!compact)
            Positioned(
              left: 16,
              bottom: 16,
              child: ValueListenableBuilder(
                valueListenable: gauge,
                builder: (context, _, _) => WindGauge(wind: world.wind),
              ),
            ),
          // Toast.
          Positioned(
            left: 0,
            right: 0,
            top: compact ? 70 : 24,
            child: IgnorePointer(
              child: ValueListenableBuilder<String?>(
                valueListenable: toast,
                builder: (context, t, _) => AnimatedOpacity(
                  opacity: t == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(t ?? '', style: UI.label),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!compact)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    'drag to orbit · right-drag or shift-drag to pan · scroll to zoom · click a house',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: Color(0x99FFFFFF),
                      shadows: [
                        Shadow(blurRadius: 6, color: Color(0x66000000)),
                      ],
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

/// Picks the panel on the left: building / house / tile tools or a hint.
extension on _CityScreenState {
  Widget _leftPanel(Lot? lot) {
    final w = world;
    if (lot != null) {
      return w.buildMode
          ? BuildingPanel(key: ValueKey(('b', lot)), world: w, lot: lot)
          : HousePanel(key: ValueKey(('h', lot)), world: w, lot: lot);
    }
    final tile = w.selectedBlock;
    if (w.buildMode && tile != null) {
      return TilePanel(key: ValueKey(('t', tile)), world: w, block: tile);
    }
    if (w.buildMode) {
      return const _Hint(
        key: ValueKey('build'),
        icon: Icons.construction,
        text:
            'Build: click a tile to change it, or a building to edit it. '
            'Ctrl+Z undoes, Esc leaves.',
      );
    }
    if (w.moveBlocks) {
      return const _Hint(
        key: ValueKey('move'),
        text: 'Move blocks: tap a block, then tap another to swap them.',
      );
    }
    return const SizedBox.shrink(key: ValueKey('none'));
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Hint({super.key, required this.text, this.icon = Icons.open_with});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      width: 232,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: UI.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: UI.label)),
        ],
      ),
    );
  }
}
