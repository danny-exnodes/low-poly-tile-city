import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'lighting.dart';
import 'scene.dart';

/// Orbit camera with perspective projection.
class Camera {
  double tx = 0, ty = 0, tz = 0;
  double yaw = -0.32;
  double pitch = 0.78;
  double dist = 300;
  double fov = 0.62;

  // Derived each frame.
  double ex = 0, ey = 0, ez = 0;
  double rx = 1, ry = 0, rz = 0;
  double ux = 0, uy = 1, uz = 0;
  double fx = 0, fy = 0, fz = -1;
  double focal = 1, cx = 0, cy = 0, w = 1, h = 1;

  void update(double width, double height) {
    w = width;
    h = height;
    cx = width / 2;
    cy = height / 2;
    focal = (height / 2) / math.tan(fov / 2);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final dx = cp * math.sin(yaw), dy = sp, dz = cp * math.cos(yaw);
    ex = tx + dx * dist;
    ey = ty + dy * dist;
    ez = tz + dz * dist;
    fx = -dx;
    fy = -dy;
    fz = -dz;
    // right = f x up
    var rl = math.sqrt(fz * fz + fx * fx);
    if (rl < 1e-6) rl = 1;
    rx = -fz / rl;
    ry = 0;
    rz = fx / rl;
    // up = r x f
    ux = ry * fz - rz * fy;
    uy = rz * fx - rx * fz;
    uz = rx * fy - ry * fx;
  }

  /// Signature used to decide if cached ground drawing is still valid.
  String get signature => '$tx,$ty,$tz,$yaw,$pitch,$dist,$fov,$w,$h';

  /// Intersects the ray through a screen point with the plane y = [py].
  (double, double)? groundHit(double sx, double sy, [double py = 0]) {
    final ax = (sx - cx) / focal, ay = -(sy - cy) / focal;
    final dx = fx + rx * ax + ux * ay;
    final dy = fy + ry * ax + uy * ay;
    final dz = fz + rz * ax + uz * ay;
    if (dy.abs() < 1e-6) return null;
    final t = (py - ey) / dy;
    if (t < 0) return null;
    return (ex + dx * t, ez + dz * t);
  }

  /// Camera space depth of a world point.
  double depth(double x, double y, double z) =>
      (x - ex) * fx + (y - ey) * fy + (z - ez) * fz;
}

class RenderStats {
  int triangles = 0;
  int drawCalls = 0;
  double cpuMs = 0;
}

/// Software painter's-algorithm renderer that batches every visible
/// triangle into a handful of [ui.Vertices] draw calls.
class Renderer {
  final cam = Camera();
  final stats = RenderStats();

  Float32List _pos = Float32List(6 * 4096);
  Int32List _col = Int32List(3 * 4096);
  Int32List _triObj = Int32List(4096);
  int _n = 0;

  // Picking data from the last frame.
  Float32List _pickPos = Float32List(0);
  Int32List _pickObj = Int32List(0);
  int _pickN = 0;
  List<SceneObject> _pickList = const [];

  ui.Picture? _groundPic;
  String _groundKey = '';

  static const _near = 0.5;

  void _ensure(int extraTris) {
    final need = _n + extraTris;
    if (need * 3 <= _col.length) return;
    var cap = _col.length ~/ 3;
    while (cap < need) {
      cap *= 2;
    }
    final p = Float32List(cap * 6)..setRange(0, _n * 6, _pos);
    final c = Int32List(cap * 3)..setRange(0, _n * 3, _col);
    final o = Int32List(cap)..setRange(0, _n, _triObj);
    _pos = p;
    _col = c;
    _triObj = o;
  }

  void _flush(ui.Canvas canvas) {
    if (_n == 0) return;
    final v = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, 0, _n * 6),
      colors: Int32List.sublistView(_col, 0, _n * 3),
    );
    canvas.drawVertices(v, ui.BlendMode.dst, ui.Paint());
    stats.drawCalls++;
    stats.triangles += _n;
  }

  /// Emits the triangles of [o] (already relit) into the batch.
  void _emit(SceneObject o, int drawId, Light light) {
    final m = o.mesh;
    final cam = this.cam;
    final cr = math.cos(o.rot), sr = math.sin(o.rot);
    final cs = math.cos(o.spin), ss = math.sin(o.spin);
    final sx = o.sx, sy = o.sy, sz = o.sz;
    // Columns of the model matrix.
    final m00 = cr * cs * sx, m10 = ss * sx, m20 = -sr * cs * sx;
    final xp = cs * sx * o.shx - ss * sy, yp = ss * sx * o.shx + cs * sy;
    final zp = sz * o.shz;
    final m01 = cr * xp + sr * zp, m11 = yp, m21 = -sr * xp + cr * zp;
    final m02 = sr * sz, m12 = 0.0, m22 = cr * sz;
    // Camera rows times model.
    final a00 = cam.rx * m00 + cam.ry * m10 + cam.rz * m20;
    final a01 = cam.rx * m01 + cam.ry * m11 + cam.rz * m21;
    final a02 = cam.rx * m02 + cam.ry * m12 + cam.rz * m22;
    final a10 = cam.ux * m00 + cam.uy * m10 + cam.uz * m20;
    final a11 = cam.ux * m01 + cam.uy * m11 + cam.uz * m21;
    final a12 = cam.ux * m02 + cam.uy * m12 + cam.uz * m22;
    final a20 = cam.fx * m00 + cam.fy * m10 + cam.fz * m20;
    final a21 = cam.fx * m01 + cam.fy * m11 + cam.fz * m21;
    final a22 = cam.fx * m02 + cam.fy * m12 + cam.fz * m22;
    final ox = o.x - cam.ex, oy = o.y - cam.ey, oz = o.z - cam.ez;
    final b0 = cam.rx * ox + cam.ry * oy + cam.rz * oz;
    final b1 = cam.ux * ox + cam.uy * oy + cam.uz * oz;
    final b2 = cam.fx * ox + cam.fy * oy + cam.fz * oz;
    final focal = cam.focal, ccx = cam.cx, ccy = cam.cy;

    final lit = o.lit!;
    final p = m.pos;
    final nrm = m.nrm;
    final hl = o.highlight;

    // Early back-face rejection with camera-space normals. Valid when the
    // model transform is (nearly) a rotation plus uniform scale.
    final early =
        o.shx.abs() < 0.25 &&
        o.shz.abs() < 0.25 &&
        (o.sx - o.sy).abs() < 0.05 &&
        (o.sz - o.sy).abs() < 0.05;
    // Rotation part only: rotY * rotZ(spin).
    final r00 = cr * cs, r01 = -cr * ss, r02 = sr;
    final r10 = ss, r11 = cs;
    final r20 = -sr * cs, r21 = sr * ss, r22 = cr;
    final n00 = cam.rx * r00 + cam.ry * r10 + cam.rz * r20;
    final n01 = cam.rx * r01 + cam.ry * r11 + cam.rz * r21;
    final n02 = cam.rx * r02 + cam.rz * r22;
    final n10 = cam.ux * r00 + cam.uy * r10 + cam.uz * r20;
    final n11 = cam.ux * r01 + cam.uy * r11 + cam.uz * r21;
    final n12 = cam.ux * r02 + cam.uz * r22;
    final n20 = cam.fx * r00 + cam.fy * r10 + cam.fz * r20;
    final n21 = cam.fx * r01 + cam.fy * r11 + cam.fz * r21;
    final n22 = cam.fx * r02 + cam.fz * r22;

    _ensure(m.triCount);
    var pos = _pos, col = _col, tob = _triObj;
    var n = _n;

    // Triangle ranges to draw, in order.
    final parts = m.partCount;
    var nr = 0;
    var rs = _ranges;
    if (rs.length < parts * 2 + 2) rs = _ranges = Int32List(parts * 2 + 64);
    if (!m.sortParts || parts <= 1) {
      rs[0] = 0;
      rs[1] = m.triCount;
      nr = 2;
    } else {
      final pb = m.partBox;
      final keys = Float64List(parts);
      for (var k = 0; k < parts; k++) {
        final lx = (pb[k * 6] + pb[k * 6 + 3]) / 2;
        final ly = (pb[k * 6 + 1] + pb[k * 6 + 4]) / 2;
        final lz = (pb[k * 6 + 2] + pb[k * 6 + 5]) / 2;
        final d = a20 * lx + a21 * ly + a22 * lz + b2;
        keys[k] = (d * 1000).floorToDouble() * 4096 + k;
      }
      keys.sort();
      for (var k = parts - 1; k >= 0; k--) {
        final pi = (keys[k] % 4096).toInt();
        rs[nr++] = m.partStart[pi];
        rs[nr++] = m.partStart[pi + 1];
      }
    }
    for (var ri = 0; ri < nr; ri += 2) {
      for (var t = rs[ri]; t < rs[ri + 1]; t++) {
        var c = lit[t];
        if (c == 0) continue;
        final i = t * 9;
        var lx = p[i], ly = p[i + 1], lz = p[i + 2];
        final z0 = a20 * lx + a21 * ly + a22 * lz + b2;
        if (z0 < _near) continue;
        final vx0 = a00 * lx + a01 * ly + a02 * lz + b0;
        final vy0 = a10 * lx + a11 * ly + a12 * lz + b1;
        if (early) {
          final k = t * 3;
          final nx = nrm[k], ny = nrm[k + 1], nz = nrm[k + 2];
          final cnx = n00 * nx + n01 * ny + n02 * nz;
          final cny = n10 * nx + n11 * ny + n12 * nz;
          final cnz = n20 * nx + n21 * ny + n22 * nz;
          if (cnx * vx0 + cny * vy0 + cnz * z0 > 0.02 * z0) continue;
        }
        final x0 = ccx + vx0 * focal / z0;
        final y0 = ccy - vy0 * focal / z0;
        lx = p[i + 3];
        ly = p[i + 4];
        lz = p[i + 5];
        final z1 = a20 * lx + a21 * ly + a22 * lz + b2;
        if (z1 < _near) continue;
        final x1 = ccx + (a00 * lx + a01 * ly + a02 * lz + b0) * focal / z1;
        final y1 = ccy - (a10 * lx + a11 * ly + a12 * lz + b1) * focal / z1;
        lx = p[i + 6];
        ly = p[i + 7];
        lz = p[i + 8];
        final z2 = a20 * lx + a21 * ly + a22 * lz + b2;
        if (z2 < _near) continue;
        final x2 = ccx + (a00 * lx + a01 * ly + a02 * lz + b0) * focal / z2;
        final y2 = ccy - (a10 * lx + a11 * ly + a12 * lz + b1) * focal / z2;
        // Back-face cull in screen space.
        if ((x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0) >= 0) continue;
        if (hl > 0) c = mixColor(c, 0xFFFFB066, hl);
        final k = n * 6;
        pos[k] = x0;
        pos[k + 1] = y0;
        pos[k + 2] = x1;
        pos[k + 3] = y1;
        pos[k + 4] = x2;
        pos[k + 5] = y2;
        final kc = n * 3;
        col[kc] = c;
        col[kc + 1] = c;
        col[kc + 2] = c;
        tob[n] = drawId;
        n++;
      }
    }
    _n = n;
  }

  /// Emits flat-coloured triangles given in world space.
  void _emitWorld(Float32List tris, int count, int color) {
    final cam = this.cam;
    _ensure(count);
    for (var t = 0; t < count; t++) {
      final i = t * 9;
      var ok = true;
      final k = _n * 6;
      for (var v = 0; v < 3; v++) {
        final dx = tris[i + v * 3] - cam.ex;
        final dy = tris[i + v * 3 + 1] - cam.ey;
        final dz = tris[i + v * 3 + 2] - cam.ez;
        final z = dx * cam.fx + dy * cam.fy + dz * cam.fz;
        if (z < _near) {
          ok = false;
          break;
        }
        _pos[k + v * 2] =
            cam.cx + (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / z;
        _pos[k + v * 2 + 1] =
            cam.cy - (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / z;
      }
      if (!ok) continue;
      _col[_n * 3] = color;
      _col[_n * 3 + 1] = color;
      _col[_n * 3 + 2] = color;
      _n++;
    }
  }

  bool _visible(SceneObject o) {
    final m = o.mesh;
    final s = math.max(o.sx, math.max(o.sy, o.sz));
    final r = m.radius * s + 1;
    final wx = o.x + m.centerX,
        wy = o.y + m.centerY * o.sy,
        wz = o.z + m.centerZ;
    final dx = wx - cam.ex, dy = wy - cam.ey, dz = wz - cam.ez;
    final z = dx * cam.fx + dy * cam.fy + dz * cam.fz;
    if (z < -r) return false;
    if (z < r) return true;
    final x = (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / z;
    final y = (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / z;
    final sr = r * cam.focal / z;
    return x + sr > -cam.cx &&
        x - sr < cam.cx &&
        y + sr > -cam.cy &&
        y - sr < cam.cy;
  }

  ui.Picture _buildGround(Scene scene) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final light = scene.light;
    final g = scene.groundObject;
    _n = 0;
    if (g != null) {
      if (g.litVersion != light.version) g.relight(light);
      _emit(g, -1, light);
      _flush(c);
    }
    _n = 0;
    final sh = scene.shadows;
    if (sh.isNotEmpty && light.shadowAlpha > 0.01) {
      _emitWorld(sh, sh.length ~/ 9, 0xFF1C2238);
      c.save();
      _clipBoard(c, scene);
      c.saveLayer(
        null,
        ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, light.shadowAlpha),
      );
      _flush(c);
      c.restore();
      c.restore();
    }
    _n = 0;
    return rec.endRecording();
  }

  /// Clips to the projected board top so shadows never spill off it.
  void _clipBoard(ui.Canvas c, Scene scene) {
    final w = scene.boardHalfW, d = scene.boardHalfD;
    final path = ui.Path();
    var k = 0;
    for (final (x, z) in [(-w, -d), (w, -d), (w, d), (-w, d)]) {
      final dx = x - cam.ex, dy = -cam.ey, dz = z - cam.ez;
      final depth = dx * cam.fx + dy * cam.fy + dz * cam.fz;
      if (depth < _near) return;
      final sx =
          cam.cx +
          (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / depth;
      final sy =
          cam.cy -
          (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / depth;
      if (k++ == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    c.clipPath(path);
  }

  Int32List _ranges = Int32List(256);
  Float64List _keys = Float64List(1024);
  final _drawList = <SceneObject>[];

  /// Renders the whole scene onto [canvas].
  void render(
    ui.Canvas canvas,
    ui.Size size,
    Scene scene, {
    bool tiltShift = true,
  }) {
    stats.triangles = 0;
    stats.drawCalls = 0;
    final sw = Stopwatch()..start();
    cam.update(size.width, size.height);
    final light = scene.light;

    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final rect = ui.Offset.zero & size;

    // Sky / table background.
    c.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset.zero,
          ui.Offset(0, size.height),
          [ui.Color(light.skyTop), ui.Color(light.skyBottom)],
        ),
    );
    stats.drawCalls++;

    // Ground layer is cached while camera and lighting are unchanged.
    final key = '${cam.signature}|${light.version}|${scene.groundVersion}';
    if (key != _groundKey || _groundPic == null) {
      _groundPic = _buildGround(scene);
      _groundKey = key;
    }
    c.drawPicture(_groundPic!);
    stats.drawCalls += 2;

    _drawMoverShadows(c, scene);
    _drawOutline(c, scene);

    // Collect objects and particles, sort far to near.
    final objs = scene.objects;
    final parts = scene.particles;
    _drawList.clear();
    var nk = 0;
    final need = objs.length + parts.count;
    if (_keys.length < need) _keys = Float64List(need * 2);
    for (final o in objs) {
      if (!o.visible) continue;
      if (!_visible(o)) continue;
      final m = o.mesh;
      final d = cam.depth(
        o.x + m.centerX,
        o.y + m.centerY * o.sy,
        o.z + m.centerZ,
      );
      _keys[nk++] = (d * 100).floorToDouble() * 65536 + _drawList.length;
      _drawList.add(o);
    }
    final pBase = 60000;
    for (var i = 0; i < parts.count; i++) {
      if (parts.state[i] == 0) continue;
      final d = cam.depth(parts.x[i], parts.y[i], parts.z[i]);
      if (d < _near) continue;
      _keys[nk++] = (d * 100).floorToDouble() * 65536 + pBase + i;
    }
    final keys = Float64List.sublistView(_keys, 0, nk)..sort();

    _n = 0;
    final pbright = light.brightness;
    for (var k = nk - 1; k >= 0; k--) {
      final id = (keys[k] % 65536).toInt();
      if (id < pBase) {
        final o = _drawList[id];
        if (o.litVersion != light.version || o.dynamicLight) o.relight(light);
        _emit(o, id, light);
      } else {
        _emitParticle(parts, id - pBase, pbright);
      }
    }
    _flush(c);

    // Keep picking data.
    if (_pickPos.length < _n * 6) {
      _pickPos = Float32List(_n * 6 + 6000);
      _pickObj = Int32List(_n + 1000);
    }
    _pickPos.setRange(0, _n * 6, _pos);
    _pickObj.setRange(0, _n, _triObj);
    _pickN = _n;
    _pickList = List.of(_drawList);
    _n = 0;

    _drawLampGlow(c, scene);

    final pic = rec.endRecording();
    stats.cpuMs = stats.cpuMs * 0.9 + sw.elapsedMicroseconds / 1000 * 0.1;
    canvas.drawPicture(pic);

    if (tiltShift) {
      // Blur a copy and keep only the top and bottom bands.
      canvas.saveLayer(
        rect,
        ui.Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 3.2,
            sigmaY: 3.2,
            tileMode: ui.TileMode.clamp,
          ),
      );
      canvas.drawPicture(pic);
      canvas.drawRect(
        rect,
        ui.Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            ui.Offset.zero,
            ui.Offset(0, size.height),
            const [
              ui.Color(0xFF000000),
              ui.Color(0x00000000),
              ui.Color(0x00000000),
              ui.Color(0xFF000000),
            ],
            const [0.0, 0.38, 0.62, 1.0],
          ),
      );
      canvas.restore();
      stats.drawCalls += 3;
    }

    // Vignette.
    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.longestSide * 0.75,
          [
            const ui.Color(0x00000000),
            ui.Color.fromRGBO(20, 10, 0, 0.22 + 0.2 * light.night),
          ],
          const [0.55, 1.0],
        ),
    );
    stats.drawCalls++;
  }

  void _emitParticle(Particles p, int i, double bright) {
    final cam = this.cam;
    final s = p.size[i];
    final a = p.ang[i];
    final ca = math.cos(a), sa = math.sin(a);
    double ax, ay, az, bx, by, bz;
    if (p.state[i] == 2) {
      // Lying flat.
      ax = ca * s;
      ay = 0;
      az = sa * s;
      bx = -sa * s * 0.55;
      by = 0;
      bz = ca * s * 0.55;
    } else {
      final f = math.sin(p.phase[i]);
      ax = ca * s;
      ay = f * s * 0.7;
      az = sa * s;
      bx = -sa * s * 0.55 * f;
      by = s * 0.55 * math.cos(p.phase[i]);
      bz = ca * s * 0.55 * f;
    }
    final px = p.x[i], py = p.y[i], pz = p.z[i];
    _ensure(2);
    final k = _n * 6;
    double? sx0, sy0;
    var ok = true;
    // Diamond: +a, +b, -a, -b.
    final pts = [
      px + ax, py + ay, pz + az, //
      px + bx, py + by, pz + bz,
      px - ax, py - ay, pz - az,
      px - bx, py - by, pz - bz,
    ];
    final scr = Float32List(8);
    for (var v = 0; v < 4; v++) {
      final dx = pts[v * 3] - cam.ex;
      final dy = pts[v * 3 + 1] - cam.ey;
      final dz = pts[v * 3 + 2] - cam.ez;
      final z = dx * cam.fx + dy * cam.fy + dz * cam.fz;
      if (z < _near) {
        ok = false;
        break;
      }
      scr[v * 2] =
          cam.cx + (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / z;
      scr[v * 2 + 1] =
          cam.cy - (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / z;
    }
    if (!ok) return;
    sx0 = scr[0];
    sy0 = scr[1];
    _pos[k] = sx0;
    _pos[k + 1] = sy0;
    _pos[k + 2] = scr[2];
    _pos[k + 3] = scr[3];
    _pos[k + 4] = scr[4];
    _pos[k + 5] = scr[5];
    _pos[k + 6] = sx0;
    _pos[k + 7] = sy0;
    _pos[k + 8] = scr[4];
    _pos[k + 9] = scr[5];
    _pos[k + 10] = scr[6];
    _pos[k + 11] = scr[7];
    var c = p.color[i];
    final kind = p.kind[i];
    final b = kind == PK.snow ? math.max(bright, 0.75) : bright;
    if (p.state[i] == 2) {
      c = scaleColor(c, b * 0.86);
    } else {
      c = scaleColor(c, b * (0.9 + 0.2 * math.cos(p.phase[i])));
    }
    final life = p.life[i];
    if (kind == PK.dust || (p.state[i] == 2 && life < 1.5)) {
      final alpha = kind == PK.dust
          ? (life.clamp(0.0, 1.0) * 200).toInt()
          : (life / 1.5 * 255).clamp(0, 255).toInt();
      c = (c & 0x00FFFFFF) | (alpha << 24);
    }
    for (var v = 0; v < 6; v++) {
      _col[_n * 3 + v] = c;
    }
    _triObj[_n] = -1;
    _triObj[_n + 1] = -1;
    _n += 2;
  }

  void _drawMoverShadows(ui.Canvas c, Scene scene) {
    final light = scene.light;
    if (light.shadowAlpha < 0.01 || scene.movers.isEmpty) return;
    final ox = -light.sx / light.sy, oz = -light.sz / light.sy;
    final tris = Float32List(scene.movers.length * 18);
    var n = 0;
    for (final o in scene.movers) {
      if (!o.visible) continue;
      final m = o.mesh;
      final h = m.maxY * o.sy * 0.6;
      final cr = math.cos(o.rot), sr = math.sin(o.rot);
      final hw = (m.maxX - m.minX) / 2 * o.sx,
          hd = (m.maxZ - m.minZ) / 2 * o.sz;
      final gy = o.y + 0.05;
      final sx = o.x + ox * h * 0.5, sz = o.z + oz * h * 0.5;
      // Rotated rectangle stretched along the light.
      final pts = <double>[];
      for (final (u, v) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
        final lx = u * hw, lz = v * hd;
        pts
          ..add(sx + cr * lx + sr * lz)
          ..add(sz - sr * lx + cr * lz);
      }
      for (final idx in const [0, 1, 2, 0, 2, 3]) {
        tris[n++] = pts[idx * 2];
        tris[n++] = gy;
        tris[n++] = pts[idx * 2 + 1];
      }
    }
    _n = 0;
    _emitWorld(tris, n ~/ 9, 0xFF1C2238);
    c.save();
    _clipBoard(c, scene);
    c.saveLayer(
      null,
      ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, light.shadowAlpha * 0.9),
    );
    _flush(c);
    c.restore();
    c.restore();
    _n = 0;
  }

  void _drawOutline(ui.Canvas c, Scene scene) {
    final o = scene.outline;
    if (o == null) return;
    final path = ui.Path();
    var k = 0;
    for (final (x, z) in [
      (o[0], o[1]),
      (o[2], o[1]),
      (o[2], o[3]),
      (o[0], o[3]),
    ]) {
      final dx = x - cam.ex, dy = o[4] - cam.ey, dz = z - cam.ez;
      final depth = dx * cam.fx + dy * cam.fy + dz * cam.fz;
      if (depth < _near) return;
      final sx =
          cam.cx +
          (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / depth;
      final sy =
          cam.cy -
          (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / depth;
      if (k++ == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    c.drawPath(path, ui.Paint()..color = const ui.Color(0x33FFB066));
    c.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const ui.Color(0x55FFB066)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    c.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const ui.Color(0xFFFFB066),
    );
    stats.drawCalls += 3;
  }

  void _drawLampGlow(ui.Canvas c, Scene scene) {
    final light = scene.light;
    if (light.night < 0.05 || scene.lamps.isEmpty) return;
    final l = scene.lamps;
    final paint = ui.Paint()..blendMode = ui.BlendMode.plus;
    for (var i = 0; i < l.length; i += 3) {
      final dx = l[i] - cam.ex, dy = l[i + 1] - cam.ey, dz = l[i + 2] - cam.ez;
      final z = dx * cam.fx + dy * cam.fy + dz * cam.fz;
      if (z < 1) continue;
      final x =
          cam.cx + (dx * cam.rx + dy * cam.ry + dz * cam.rz) * cam.focal / z;
      final y =
          cam.cy - (dx * cam.ux + dy * cam.uy + dz * cam.uz) * cam.focal / z;
      final r = 7 * cam.focal / z;
      if (x < -r || y < -r || x > cam.w + r || y > cam.h + r) continue;
      paint.shader = ui.Gradient.radial(ui.Offset(x, y), r, [
        ui.Color.fromRGBO(255, 190, 110, 0.5 * light.night),
        const ui.Color(0x00000000),
      ]);
      c.drawCircle(ui.Offset(x, y), r, paint);
    }
    stats.drawCalls++;
  }

  /// Returns the topmost object under a screen point from the last frame.
  SceneObject? pick(double x, double y) {
    for (var t = _pickN - 1; t >= 0; t--) {
      final id = _pickObj[t];
      if (id < 0) continue;
      final k = t * 6;
      final x0 = _pickPos[k], y0 = _pickPos[k + 1];
      final x1 = _pickPos[k + 2], y1 = _pickPos[k + 3];
      final x2 = _pickPos[k + 4], y2 = _pickPos[k + 5];
      final d1 = (x - x1) * (y0 - y1) - (x0 - x1) * (y - y1);
      final d2 = (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2);
      final d3 = (x - x0) * (y2 - y0) - (x2 - x0) * (y - y0);
      final neg = d1 < 0 || d2 < 0 || d3 < 0;
      final pos = d1 > 0 || d2 > 0 || d3 > 0;
      if (!(neg && pos)) return _pickList[id];
    }
    return null;
  }
}
