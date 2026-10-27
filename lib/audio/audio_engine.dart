import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../engine/lighting.dart';
import '../world/world.dart';

/// Procedural ambience (wind, leaves, birds, traffic) and generative music
/// built directly on the Web Audio API.
class AudioEngine {
  web.AudioContext? _ctx;
  late web.GainNode _sfx, _music;
  late web.AudioBuffer _noise;
  late web.BiquadFilterNode _windFilter, _whistleFilter;
  late web.GainNode _windGain, _whistleGain, _rustleGain, _humGain;
  web.DelayNode? _delay;
  final _r = math.Random();

  bool _soundOn = false, _musicOn = false;
  int _buildSeen = 0, _gustSeen = 0, _devilSeen = 0, _swapSeen = 0;
  double _nextBird = 0, _nextCricket = 0, _nextHorn = 0, _nextBeat = 0;
  int _beat = 0;
  double _hammerUntil = 0, _nextHammer = 0;

  double get _now => _ctx!.currentTime;

  void _ensure() {
    if (_ctx != null) return;
    final ctx = web.AudioContext();
    _ctx = ctx;
    final master = ctx.createGain()..gain.value = 0.9;
    master.connect(ctx.destination);
    _sfx = ctx.createGain()..gain.value = 0;
    _sfx.connect(master);
    _music = ctx.createGain()..gain.value = 0;
    _music.connect(master);

    // Two seconds of white noise, looped by every noise source.
    final n = (ctx.sampleRate * 2).toInt();
    _noise = ctx.createBuffer(1, n, ctx.sampleRate);
    final data = Float32List(n);
    for (var i = 0; i < n; i++) {
      data[i] = _r.nextDouble() * 2 - 1;
    }
    _noise.copyToChannel(data.toJS, 0);

    // Wind body.
    _windFilter = ctx.createBiquadFilter()
      ..type = 'bandpass'
      ..Q.value = 0.6;
    _windGain = ctx.createGain()..gain.value = 0;
    _noiseSource().connect(_windFilter);
    _windFilter.connect(_windGain);
    _windGain.connect(_sfx);

    // Whistle for strong wind.
    _whistleFilter = ctx.createBiquadFilter()
      ..type = 'bandpass'
      ..Q.value = 9;
    _whistleGain = ctx.createGain()..gain.value = 0;
    _noiseSource().connect(_whistleFilter);
    _whistleFilter.connect(_whistleGain);
    _whistleGain.connect(_sfx);

    // Leaf rustle.
    final hp = ctx.createBiquadFilter()
      ..type = 'highpass'
      ..frequency.value = 3200;
    _rustleGain = ctx.createGain()..gain.value = 0;
    _noiseSource().connect(hp);
    hp.connect(_rustleGain);
    _rustleGain.connect(_sfx);

    // Distant city hum.
    final lp = ctx.createBiquadFilter()
      ..type = 'lowpass'
      ..frequency.value = 160;
    _humGain = ctx.createGain()..gain.value = 0;
    _noiseSource().connect(lp);
    lp.connect(_humGain);
    _humGain.connect(_sfx);

    // Echo for music.
    final delay = ctx.createDelay(2)..delayTime.value = 0.42;
    final fb = ctx.createGain()..gain.value = 0.32;
    final wet = ctx.createGain()..gain.value = 0.35;
    delay.connect(fb);
    fb.connect(delay);
    delay.connect(wet);
    wet.connect(_music);
    _delay = delay;
  }

  web.AudioBufferSourceNode _noiseSource() {
    final s = _ctx!.createBufferSource()
      ..buffer = _noise
      ..loop = true;
    s.start(0, _r.nextDouble() * 1.9);
    return s;
  }

  /// Called every frame with the current world state.
  void tick(World w) {
    final wantSound = w.sound, wantMusic = w.music;
    if (!wantSound && !wantMusic && _ctx == null) return;
    _ensure();
    final ctx = _ctx!;
    if (ctx.state == 'suspended') ctx.resume();
    final now = _now;

    if (wantSound != _soundOn) {
      _soundOn = wantSound;
      _sfx.gain.setTargetAtTime(wantSound ? 1 : 0, now, 0.3);
    }
    if (wantMusic != _musicOn) {
      _musicOn = wantMusic;
      _music.gain.setTargetAtTime(wantMusic ? 0.55 : 0, now, 0.5);
      _nextBeat = now + 0.1;
    }

    if (_soundOn) _ambience(w, now);
    if (_musicOn) _scheduleMusic(now);
  }

  void _ambience(World w, double now) {
    final s = w.wind.speed;
    _windFilter.frequency.setTargetAtTime(220 + s * 45, now, 0.2);
    _windGain.gain.setTargetAtTime(0.03 + s * 0.016, now, 0.25);
    _whistleFilter.frequency.setTargetAtTime(500 + s * 70, now, 0.3);
    _whistleGain.gain.setTargetAtTime(math.max(0, s - 7) * 0.012, now, 0.3);
    final leafy = w.season == Season.winter ? 0.2 : 1.0;
    _rustleGain.gain.setTargetAtTime(
      (0.004 + s * 0.0025) * leafy * (0.6 + 0.4 * math.sin(now * 2.7)),
      now,
      0.15,
    );
    final night = w.light.night;
    _humGain.gain.setTargetAtTime(
      0.05 * w.trafficAmount.clamp(0, 3) * (1 - 0.6 * night),
      now,
      0.5,
    );

    final birdsOk = night < 0.4 && w.season != Season.winter;
    if (birdsOk && now > _nextBird) {
      _bird(now);
      _nextBird = now + 0.8 + _r.nextDouble() * 3.5;
    }
    if (night > 0.6 && w.season != Season.winter && now > _nextCricket) {
      _cricket(now);
      _nextCricket = now + 0.6 + _r.nextDouble() * 0.8;
    }
    if (w.trafficAmount > 0.2 && now > _nextHorn) {
      if (_nextHorn > 0) _horn(now);
      _nextHorn = now + 12 + _r.nextDouble() * 25 / w.trafficAmount;
    }

    if (w.buildEvents != _buildSeen) {
      _buildSeen = w.buildEvents;
      _whoosh(now, 1.2, 0.25);
      _hammerUntil = now + 1.8;
    }
    if (now < _hammerUntil && now > _nextHammer) {
      _hammer(now);
      _nextHammer = now + 0.16 + _r.nextDouble() * 0.12;
    }
    if (w.gustEvents != _gustSeen) {
      _gustSeen = w.gustEvents;
      _whoosh(now, 4.5, 0.5);
    }
    if (w.devilEvents != _devilSeen) {
      _devilSeen = w.devilEvents;
      _whoosh(now, 6, 0.35);
    }
    if (w.swapEvents != _swapSeen) {
      _swapSeen = w.swapEvents;
      _thump(now + 0.3);
    }
  }

  web.GainNode _env(
    double t,
    double peak,
    double attack,
    double decay,
    web.AudioNode dest,
  ) {
    final g = _ctx!.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
    g.connect(dest);
    return g;
  }

  void _bird(double t) {
    final ctx = _ctx!;
    final chirps = 2 + _r.nextInt(4);
    final base = 2600 + _r.nextDouble() * 1800;
    for (var k = 0; k < chirps; k++) {
      final t0 = t + k * (0.09 + _r.nextDouble() * 0.05);
      final o = ctx.createOscillator()..type = 'sine';
      o.frequency.setValueAtTime(base, t0);
      o.frequency.exponentialRampToValueAtTime(base * 1.45, t0 + 0.05);
      o.frequency.exponentialRampToValueAtTime(base * 0.9, t0 + 0.08);
      o.connect(_env(t0, 0.035, 0.01, 0.07, _sfx));
      o.start(t0);
      o.stop(t0 + 0.12);
    }
  }

  void _cricket(double t) {
    final ctx = _ctx!;
    for (var k = 0; k < 3; k++) {
      final t0 = t + k * 0.05;
      final o = ctx.createOscillator()..type = 'triangle';
      o.frequency.value = 4400 + _r.nextDouble() * 200;
      o.connect(_env(t0, 0.012, 0.005, 0.03, _sfx));
      o.start(t0);
      o.stop(t0 + 0.05);
    }
  }

  void _horn(double t) {
    final ctx = _ctx!;
    final lp = ctx.createBiquadFilter()
      ..type = 'lowpass'
      ..frequency.value = 1400;
    lp.connect(_sfx);
    for (final f in const [392.0, 494.0]) {
      final o = ctx.createOscillator()..type = 'square';
      o.frequency.value = f;
      o.connect(_env(t, 0.012, 0.02, 0.28, lp));
      o.start(t);
      o.stop(t + 0.35);
    }
  }

  void _hammer(double t) {
    final ctx = _ctx!;
    final s = ctx.createBufferSource()..buffer = _noise;
    final bp = ctx.createBiquadFilter()
      ..type = 'bandpass'
      ..frequency.value = 900 + _r.nextDouble() * 900
      ..Q.value = 4;
    s.connect(bp);
    bp.connect(_env(t, 0.5, 0.003, 0.08, _sfx));
    s.start(t, _r.nextDouble());
    s.stop(t + 0.1);
  }

  void _whoosh(double t, double len, double peak) {
    final ctx = _ctx!;
    final s = ctx.createBufferSource()
      ..buffer = _noise
      ..loop = true;
    final bp = ctx.createBiquadFilter()
      ..type = 'bandpass'
      ..Q.value = 1.2;
    bp.frequency.setValueAtTime(250, t);
    bp.frequency.exponentialRampToValueAtTime(900, t + len * 0.5);
    bp.frequency.exponentialRampToValueAtTime(300, t + len);
    s.connect(bp);
    bp.connect(_env(t, peak, len * 0.4, len * 0.6, _sfx));
    s.start(t);
    s.stop(t + len + 0.1);
  }

  void _thump(double t) {
    final ctx = _ctx!;
    final o = ctx.createOscillator()..type = 'sine';
    o.frequency.setValueAtTime(120, t);
    o.frequency.exponentialRampToValueAtTime(45, t + 0.3);
    o.connect(_env(t, 0.6, 0.005, 0.4, _sfx));
    o.start(t);
    o.stop(t + 0.5);
  }

  // ---------------------------------------------------------------------
  // Generative music: slow I-vi-IV-V with pentatonic plucks.

  static const _bpm = 76.0;
  static const _chords = [
    [60, 64, 67, 71], // Cmaj7
    [57, 60, 64, 67], // Am7
    [53, 57, 60, 64], // Fmaj7
    [55, 59, 62, 69], // G6/9-ish
  ];
  static const _penta = [72, 74, 76, 79, 81, 84, 86, 88];
  int _melodyIdx = 3;

  double _hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

  void _scheduleMusic(double now) {
    const step = 60 / _bpm / 2; // eighth notes
    while (_nextBeat < now + 0.4) {
      final t = _nextBeat;
      final bar = _beat ~/ 8;
      final chord = _chords[(bar ~/ 2) % _chords.length];
      if (_beat % 16 == 0) {
        for (final n in chord) {
          _pad(t, _hz(n), step * 16);
        }
        _bass(t, _hz(chord[0] - 24), step * 8);
      } else if (_beat % 16 == 8) {
        _bass(t, _hz(chord[0] - 24), step * 8);
      }
      final chance = _beat % 2 == 0 ? 0.55 : 0.25;
      if (_r.nextDouble() < chance) {
        _melodyIdx = (_melodyIdx + _r.nextInt(5) - 2).clamp(
          0,
          _penta.length - 1,
        );
        _pluck(t, _hz(_penta[_melodyIdx]));
      }
      if (_beat % 4 == 2 && _r.nextDouble() < 0.5) {
        _pluck(t, _hz(chord[_r.nextInt(chord.length)] + 12), soft: true);
      }
      _beat++;
      _nextBeat += step;
    }
  }

  void _pad(double t, double f, double len) {
    final ctx = _ctx!;
    final lp = ctx.createBiquadFilter()
      ..type = 'lowpass'
      ..frequency.value = 900;
    final g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.028, t + 1.6);
    g.gain.setValueAtTime(0.028, t + len - 0.2);
    g.gain.linearRampToValueAtTime(0.0001, t + len + 1.8);
    lp.connect(g);
    g.connect(_music);
    for (final d in const [-5.0, 5.0]) {
      final o = ctx.createOscillator()..type = 'triangle';
      o.frequency.value = f;
      o.detune.value = d;
      o.connect(lp);
      o.start(t);
      o.stop(t + len + 2);
    }
  }

  void _bass(double t, double f, double len) {
    final ctx = _ctx!;
    final o = ctx.createOscillator()..type = 'sine';
    o.frequency.value = f;
    o.connect(_env(t, 0.12, 0.04, len, _music));
    o.start(t);
    o.stop(t + len + 0.1);
  }

  void _pluck(double t, double f, {bool soft = false}) {
    final ctx = _ctx!;
    final o = ctx.createOscillator()..type = soft ? 'sine' : 'triangle';
    o.frequency.value = f;
    final g = _env(t, soft ? 0.03 : 0.06, 0.008, soft ? 0.8 : 1.3, _music);
    g.connect(_delay!);
    o.connect(g);
    o.start(t);
    o.stop(t + 1.5);
  }

  void dispose() {
    _ctx?.close();
  }
}
